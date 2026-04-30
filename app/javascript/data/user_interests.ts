import { cast } from "ts-safe-cast";

import { CardProduct } from "$app/parsers/product";
import { request, ResponseError } from "$app/utils/request";

export type TaxonomySummary = {
  id: number;
  slug: string;
  label: string;
};

export type DeclaredInterest = {
  id: number;
  taxonomy: TaxonomySummary;
  source_text: string | null;
};

export type TasteProfile = {
  dominant_taxonomy: TaxonomySummary | null;
  unexplored_top_levels: TaxonomySummary[];
  declared_interests: DeclaredInterest[];
};

export type RecommendedProduct = CardProduct & {
  recommendation_reason: string;
};

export type AddInterestResponse = {
  declared_interests: DeclaredInterest[];
};

export type RecommendationsResponse = {
  taxonomy: TaxonomySummary;
  products: RecommendedProduct[];
};

type ErrorBody = { error?: string };

const USER_INTERESTS_BASE = "/user_interests";

const errorMessage = async (response: Response, fallback: string): Promise<string> => {
  try {
    const body = cast<ErrorBody>(await response.json());
    return body.error ?? fallback;
  } catch {
    return fallback;
  }
};

export async function addInterestByTaxonomy(taxonomyId: number): Promise<AddInterestResponse> {
  const response = await request({
    url: USER_INTERESTS_BASE,
    method: "POST",
    accept: "json",
    data: { taxonomy_id: taxonomyId },
  });
  if (!response.ok) throw new ResponseError(await errorMessage(response, "Couldn't add that interest."));
  return cast<AddInterestResponse>(await response.json());
}

export async function addInterestByFreeText(freeText: string): Promise<AddInterestResponse> {
  const response = await request({
    url: USER_INTERESTS_BASE,
    method: "POST",
    accept: "json",
    data: { free_text: freeText },
  });
  if (!response.ok) {
    throw new ResponseError(await errorMessage(response, "We couldn't find a matching category for that."));
  }
  return cast<AddInterestResponse>(await response.json());
}

export async function removeInterest(interestId: number): Promise<void> {
  const response = await request({
    url: `${USER_INTERESTS_BASE}/${interestId}`,
    method: "DELETE",
    accept: "json",
  });
  if (!response.ok) throw new ResponseError();
}

export async function fetchInterestRecommendations(taxonomyId: number): Promise<RecommendationsResponse> {
  const response = await request({
    url: `${USER_INTERESTS_BASE}/recommendations?taxonomy_id=${taxonomyId}`,
    method: "GET",
    accept: "json",
  });
  if (!response.ok) throw new ResponseError();
  return cast<RecommendationsResponse>(await response.json());
}
