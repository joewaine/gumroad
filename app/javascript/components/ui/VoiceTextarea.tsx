import * as React from "react";

import { transcribeAudio } from "$app/data/transcriptions";
import { classNames } from "$app/utils/classNames";
import { assertResponseError } from "$app/utils/request";
import {
  getSpeechRecognitionCtor,
  isMediaRecorderSupported,
  type SpeechRecognition,
  type SpeechRecognitionErrorEvent,
  type SpeechRecognitionEvent,
} from "$app/utils/speechRecognition";

import { Textarea } from "$app/components/ui/Textarea";

const MAX_RECORDING_MS = 5 * 60 * 1000;

type Status = "idle" | "recording" | "transcribing" | "denied" | "error";

type VoiceTextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement> & {
  voiceLabel?: string;
  onTranscript?: (text: string) => void;
};

export const VoiceTextarea = React.forwardRef<HTMLTextAreaElement, VoiceTextareaProps>(
  ({ voiceLabel, onTranscript, value, onChange, className, disabled, ...props }, ref) => {
    const [status, setStatus] = React.useState<Status>("idle");
    const [interim, setInterim] = React.useState("");
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);

    const mediaRecorderRef = React.useRef<MediaRecorder | null>(null);
    const streamRef = React.useRef<MediaStream | null>(null);
    const chunksRef = React.useRef<Blob[]>([]);
    const recognitionRef = React.useRef<SpeechRecognition | null>(null);
    const finalTranscriptRef = React.useRef("");
    const stopTimeoutRef = React.useRef<number | null>(null);

    const speechSupported = React.useMemo(() => !!getSpeechRecognitionCtor(), []);
    const recordingSupported = React.useMemo(() => speechSupported || isMediaRecorderSupported(), [speechSupported]);
    const inputDisabled = !!disabled || status === "transcribing";

    const cleanupStream = React.useCallback(() => {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }, []);

    const cleanupTimer = React.useCallback(() => {
      if (stopTimeoutRef.current !== null) {
        window.clearTimeout(stopTimeoutRef.current);
        stopTimeoutRef.current = null;
      }
    }, []);

    React.useEffect(
      () => () => {
        recognitionRef.current?.abort();
        if (mediaRecorderRef.current && mediaRecorderRef.current.state !== "inactive") {
          mediaRecorderRef.current.stop();
        }
        cleanupStream();
        cleanupTimer();
      },
      [cleanupStream, cleanupTimer],
    );

    const appendTranscript = (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      onTranscript?.(trimmed);
    };

    const startSpeechRecognition = () => {
      const Ctor = getSpeechRecognitionCtor();
      if (!Ctor) return;
      try {
        const recog = new Ctor();
        recog.lang = navigator.language || "en-US";
        recog.interimResults = true;
        recog.continuous = true;

        recog.onresult = (e: SpeechRecognitionEvent) => {
          let finalText = "";
          let interimText = "";
          for (let i = e.resultIndex; i < e.results.length; i++) {
            const result = e.results[i];
            if (!result) continue;
            const alternative = result[0];
            if (!alternative) continue;
            if (result.isFinal) finalText += alternative.transcript;
            else interimText += alternative.transcript;
          }
          if (finalText) finalTranscriptRef.current += `${finalText} `;
          setInterim((finalTranscriptRef.current + interimText).trim());
        };

        recog.onerror = (e: SpeechRecognitionErrorEvent) => {
          if (e.error !== "no-speech" && e.error !== "aborted") {
            recognitionRef.current = null;
          }
        };

        recog.start();
        recognitionRef.current = recog;
      } catch {
        recognitionRef.current = null;
      }
    };

    const startRecording = async () => {
      setErrorMessage(null);
      finalTranscriptRef.current = "";
      setInterim("");
      chunksRef.current = [];

      if (!isMediaRecorderSupported() && !speechSupported) {
        setErrorMessage("Voice input isn't supported in this browser.");
        return;
      }

      try {
        if (isMediaRecorderSupported()) {
          const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
          streamRef.current = stream;

          const recorder = new MediaRecorder(stream);
          mediaRecorderRef.current = recorder;

          recorder.ondataavailable = (e) => {
            if (e.data.size > 0) chunksRef.current.push(e.data);
          };

          recorder.onstop = () => {
            cleanupStream();

            const browserTranscript = finalTranscriptRef.current.trim();
            if (browserTranscript) {
              appendTranscript(browserTranscript);
              setStatus("idle");
              return;
            }

            const blob = new Blob(chunksRef.current, { type: recorder.mimeType || "audio/webm" });
            if (blob.size === 0) {
              setStatus("idle");
              return;
            }

            void serverTranscribe(blob);
          };

          recorder.start();
        }

        if (speechSupported) startSpeechRecognition();

        setStatus("recording");

        stopTimeoutRef.current = window.setTimeout(() => {
          stopRecording();
        }, MAX_RECORDING_MS);
      } catch {
        cleanupStream();
        setStatus("denied");
        setErrorMessage("Mic access denied. You can still type your review.");
      }
    };

    const stopRecording = () => {
      cleanupTimer();
      recognitionRef.current?.stop();
      recognitionRef.current = null;

      if (mediaRecorderRef.current && mediaRecorderRef.current.state !== "inactive") {
        mediaRecorderRef.current.stop();
        setStatus("transcribing");
      } else {
        const browserTranscript = finalTranscriptRef.current.trim();
        if (browserTranscript) appendTranscript(browserTranscript);
        cleanupStream();
        setStatus("idle");
      }
    };

    const serverTranscribe = async (blob: Blob) => {
      setStatus("transcribing");
      try {
        const text = await transcribeAudio({ audio: blob });
        appendTranscript(text);
        setStatus("idle");
      } catch (err) {
        assertResponseError(err);
        setErrorMessage(err.message || "Couldn't transcribe — please type instead.");
        setStatus("error");
      }
    };

    const handleMicClick = () => {
      if (status === "recording") stopRecording();
      else void startRecording();
    };

    const isRecording = status === "recording";
    const isTranscribing = status === "transcribing";

    const buttonLabel = isRecording
      ? "Stop recording"
      : isTranscribing
        ? "Transcribing"
        : voiceLabel || "Record voice review";

    return (
      <div className="relative w-full">
        <Textarea
          ref={ref}
          value={value}
          onChange={onChange}
          disabled={inputDisabled}
          className={classNames(recordingSupported && "pr-12", className)}
          aria-describedby={errorMessage ? `${props.id ?? "voice-textarea"}-error` : undefined}
          {...props}
        />

        {recordingSupported ? (
          <button
            type="button"
            onClick={handleMicClick}
            disabled={inputDisabled || isTranscribing}
            aria-label={buttonLabel}
            aria-pressed={isRecording}
            className={classNames(
              "absolute right-2 bottom-2 inline-flex h-8 w-8 items-center justify-center rounded-full border transition-colors",
              "focus:outline-2 focus:outline-offset-1 focus:outline-accent",
              "disabled:cursor-not-allowed disabled:opacity-40",
              isRecording
                ? "border-accent bg-accent text-background"
                : "border-border bg-background text-muted hover:border-foreground hover:text-foreground",
            )}
          >
            {isTranscribing ? <SpinnerIcon /> : isRecording ? <StopIcon /> : <MicIcon />}
          </button>
        ) : null}

        {isRecording && interim ? (
          <div className="mt-2 text-sm text-muted italic" aria-live="polite">
            “{interim}”
          </div>
        ) : null}

        {isRecording ? (
          <div role="status" className="sr-only">
            Recording. Click again to stop.
          </div>
        ) : null}

        {isTranscribing ? (
          <div role="status" className="mt-2 text-sm text-muted">
            Transcribing your recording…
          </div>
        ) : null}

        {errorMessage ? (
          <div id={`${props.id ?? "voice-textarea"}-error`} role="alert" className="mt-2 text-sm text-red">
            {errorMessage}
          </div>
        ) : null}
      </div>
    );
  },
);

VoiceTextarea.displayName = "VoiceTextarea";

const MicIcon = () => (
  <svg
    width="16"
    height="16"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={1.75}
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
  >
    <rect x="9" y="3" width="6" height="12" rx="3" />
    <path d="M5 11a7 7 0 0 0 14 0" />
    <path d="M12 18v3" />
    <path d="M9 21h6" />
  </svg>
);

const StopIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <rect x="6" y="6" width="12" height="12" rx="1.5" />
  </svg>
);

const SpinnerIcon = () => (
  <svg
    width="14"
    height="14"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={2}
    strokeLinecap="round"
    aria-hidden="true"
    className="animate-spin"
  >
    <path d="M12 3a9 9 0 1 1-6.36 2.64" />
  </svg>
);
