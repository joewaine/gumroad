import { cast } from "ts-safe-cast";

import { request, ResponseError } from "$app/utils/request";

export const transcribeAudio = async ({ audio, language }: { audio: Blob; language?: string }): Promise<string> => {
  const formData = new FormData();
  formData.append("audio", audio, audio instanceof File ? audio.name : "voice.webm");
  if (language) formData.append("language", language);

  const response = await request({
    method: "POST",
    url: Routes.internal_transcriptions_path(),
    accept: "json",
    data: formData,
  });

  const json = cast<{ success: true; text: string } | { success: false; error: string }>(await response.json());

  if (!json.success) throw new ResponseError(json.error);

  return json.text;
};
