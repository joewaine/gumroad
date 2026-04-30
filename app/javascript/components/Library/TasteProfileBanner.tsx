import { Plus, X } from "@boxicons/react";
import * as React from "react";

import {
  AddInterestResponse,
  DeclaredInterest,
  TasteProfile,
  TaxonomySummary,
  addInterestByFreeText,
  addInterestByTaxonomy,
  removeInterest,
} from "$app/data/user_interests";
import { classNames } from "$app/utils/classNames";
import { asyncVoid } from "$app/utils/promise";
import { assertResponseError, ResponseError } from "$app/utils/request";

import { showAlert } from "$app/components/server-components/Alert";
import { Input } from "$app/components/ui/Input";

const FREE_TEXT_MAX_LENGTH = 200;

type Props = {
  profile: TasteProfile;
  activeInterestId: number | null;
  onProfileChange: (profile: TasteProfile) => void;
  onActiveInterestChange: (interestId: number) => void;
};

export const TasteProfileBanner = ({ profile, activeInterestId, onProfileChange, onActiveInterestChange }: Props) => {
  const [freeTextOpen, setFreeTextOpen] = React.useState(false);
  const [freeText, setFreeText] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  const handleAddByTaxonomy = asyncVoid(async (taxonomy: TaxonomySummary) => {
    if (submitting) return;
    setSubmitting(true);
    try {
      const response = await addInterestByTaxonomy(taxonomy.id);
      applyAddedInterests(response);
    } catch (e) {
      assertResponseError(e);
      showAlert(e instanceof ResponseError ? e.message : "Couldn't add that interest.", "error");
    } finally {
      setSubmitting(false);
    }
  });

  const handleAddByFreeText = asyncVoid(async () => {
    if (submitting) return;
    const trimmed = freeText.trim();
    if (!trimmed) return;
    setSubmitting(true);
    try {
      const response = await addInterestByFreeText(trimmed);
      applyAddedInterests(response);
      setFreeText("");
      setFreeTextOpen(false);
    } catch (e) {
      assertResponseError(e);
      showAlert(e instanceof ResponseError ? e.message : "Couldn't add that interest.", "error");
    } finally {
      setSubmitting(false);
    }
  });

  const handleRemove = asyncVoid(async (interest: DeclaredInterest) => {
    if (submitting) return;
    setSubmitting(true);
    try {
      await removeInterest(interest.id);
      const remaining = profile.declared_interests.filter((i) => i.id !== interest.id);
      const restoredUnexplored = remaining.some((i) => i.taxonomy.id === interest.taxonomy.id)
        ? profile.unexplored_top_levels
        : [...profile.unexplored_top_levels, interest.taxonomy].sort((a, b) => a.label.localeCompare(b.label));
      onProfileChange({
        ...profile,
        declared_interests: remaining,
        unexplored_top_levels: restoredUnexplored,
      });
      const next = remaining[0];
      if (activeInterestId === interest.id && next) {
        onActiveInterestChange(next.id);
      }
    } catch (e) {
      assertResponseError(e);
      showAlert("Couldn't remove that interest.", "error");
    } finally {
      setSubmitting(false);
    }
  });

  const applyAddedInterests = (response: AddInterestResponse) => {
    const newInterests = response.declared_interests.filter(
      (i) => !profile.declared_interests.some((existing) => existing.id === i.id),
    );
    const first = newInterests[0];
    if (!first) return;

    const declared = [...profile.declared_interests, ...newInterests];
    const newTaxonomyIds = new Set(newInterests.map((i) => i.taxonomy.id));
    const unexplored = profile.unexplored_top_levels.filter((t) => !newTaxonomyIds.has(t.id));

    onProfileChange({ ...profile, declared_interests: declared, unexplored_top_levels: unexplored });
    onActiveInterestChange(first.id);
  };

  const dominant = profile.dominant_taxonomy;
  const hasDeclared = profile.declared_interests.length > 0;

  return (
    <section aria-label="Branch out" className="rounded-md border border-border bg-background p-4 md:p-6">
      <div className="flex flex-col gap-3">
        <p className="text-base md:text-lg">
          {dominant ? (
            <>
              You've found Gumroad through <strong>{dominant.label}</strong>.{" "}
              <span className="text-muted">What else are you curious about?</span>
            </>
          ) : (
            <>
              <span className="font-medium">What else are you curious about?</span>{" "}
              <span className="text-muted">Pick a category to branch out.</span>
            </>
          )}
        </p>

        {hasDeclared ? (
          <div
            className="flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] md:flex-wrap md:overflow-x-visible [&::-webkit-scrollbar]:hidden"
            role="tablist"
            aria-label="Your declared interests"
          >
            {profile.declared_interests.map((interest) => {
              const isActive = interest.id === activeInterestId;
              return (
                <div
                  key={interest.id}
                  className={classNames(
                    "inline-flex shrink-0 items-center gap-1 rounded-full border px-3 py-1.5 text-sm transition",
                    isActive
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-background text-foreground hover:bg-muted/30",
                  )}
                >
                  <button
                    type="button"
                    role="tab"
                    aria-selected={isActive}
                    className="cursor-pointer all-unset"
                    onClick={() => onActiveInterestChange(interest.id)}
                  >
                    {interest.taxonomy.label}
                  </button>
                  <button
                    type="button"
                    aria-label={`Remove ${interest.taxonomy.label}`}
                    className="cursor-pointer all-unset"
                    onClick={() => handleRemove(interest)}
                    disabled={submitting}
                  >
                    <X className="size-4 opacity-70 hover:opacity-100" />
                  </button>
                </div>
              );
            })}
          </div>
        ) : null}

        <div
          className="flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] md:flex-wrap md:overflow-x-visible [&::-webkit-scrollbar]:hidden"
          aria-label="Suggested categories"
        >
          {profile.unexplored_top_levels.map((taxonomy) => (
            <button
              key={taxonomy.id}
              type="button"
              className="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-full border border-border bg-background px-3 py-1.5 text-sm all-unset hover:bg-muted/30 disabled:opacity-50"
              onClick={() => handleAddByTaxonomy(taxonomy)}
              disabled={submitting}
            >
              <Plus className="size-4" />
              {taxonomy.label}
            </button>
          ))}
          {freeTextOpen ? (
            <form
              className="flex shrink-0 items-center gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                handleAddByFreeText();
              }}
            >
              <Input
                type="text"
                value={freeText}
                onChange={(e) => setFreeText(e.target.value)}
                placeholder="e.g. rock climbing, watercolor"
                maxLength={FREE_TEXT_MAX_LENGTH}
                autoFocus
                className="h-8 w-56 text-sm"
              />
              <button
                type="submit"
                className="cursor-pointer rounded-full bg-primary px-3 py-1.5 text-sm text-primary-foreground all-unset disabled:opacity-50"
                disabled={submitting || !freeText.trim()}
              >
                Add
              </button>
              <button
                type="button"
                className="cursor-pointer rounded-full border border-border px-3 py-1.5 text-sm all-unset"
                onClick={() => {
                  setFreeText("");
                  setFreeTextOpen(false);
                }}
              >
                Cancel
              </button>
            </form>
          ) : (
            <button
              type="button"
              className="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-full border border-dashed border-border bg-background px-3 py-1.5 text-sm all-unset hover:bg-muted/30"
              onClick={() => setFreeTextOpen(true)}
            >
              <Plus className="size-4" />
              Other…
            </button>
          )}
        </div>
      </div>
    </section>
  );
};
