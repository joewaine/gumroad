import { ArrowLeft, ArrowRight } from "@boxicons/react";
import * as React from "react";

import { fetchInterestRecommendations, RecommendedProduct, TaxonomySummary } from "$app/data/user_interests";
import { assertResponseError } from "$app/utils/request";

import { HorizontalCard } from "$app/components/Product/Card";
import { Skeleton } from "$app/components/Skeleton";
import { useScrollableCarousel } from "$app/components/useScrollableCarousel";

const SKELETON_COUNT = 3;
const MAX_REASON_DISPLAY_LENGTH = 70;

const trimReason = (raw: string): string =>
  raw.length > MAX_REASON_DISPLAY_LENGTH ? `${raw.slice(0, MAX_REASON_DISPLAY_LENGTH - 1).trimEnd()}…` : raw;

type Props = {
  taxonomy: TaxonomySummary;
};

export const BranchingOutCarousel = ({ taxonomy }: Props) => {
  const [products, setProducts] = React.useState<RecommendedProduct[] | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [active, setActive] = React.useState(0);
  const { itemsRef, handleScroll } = useScrollableCarousel(active, setActive);
  const [dragStart, setDragStart] = React.useState<number | null>(null);

  React.useEffect(() => {
    let canceled = false;
    setProducts(null);
    setError(null);
    setActive(0);
    const load = async () => {
      try {
        const response = await fetchInterestRecommendations(taxonomy.id);
        if (!canceled) setProducts(response.products);
      } catch (e) {
        assertResponseError(e);
        if (!canceled) setError("We couldn't load recommendations right now.");
      }
    };
    void load();
    return () => {
      canceled = true;
    };
  }, [taxonomy.id]);

  const headerLine = `Branching out into ${taxonomy.label}`;

  if (error) {
    return (
      <section className="grid gap-4">
        <header>
          <h2>{headerLine}</h2>
        </header>
        <p className="text-muted">{error}</p>
      </section>
    );
  }

  const isLoading = products === null;

  if (!isLoading && products.length === 0) {
    return (
      <section className="grid gap-4">
        <header>
          <h2>{headerLine}</h2>
        </header>
        <p className="text-muted">Nothing to show here yet — try another category.</p>
      </section>
    );
  }

  return (
    <section className="grid gap-4">
      <header className="flex items-center justify-between gap-3">
        <h2 className="min-w-0 flex-1 truncate">{headerLine}</h2>
        {!isLoading && products.length > 0 ? (
          <div className="flex shrink-0 items-center gap-2 whitespace-nowrap">
            <button
              type="button"
              aria-label="Previous"
              className="cursor-pointer all-unset"
              onClick={() => setActive((active + products.length - 1) % products.length)}
            >
              <ArrowLeft className="size-6" />
            </button>
            <span>
              {active + 1} / {products.length}
            </span>
            <button
              type="button"
              aria-label="Next"
              className="cursor-pointer all-unset"
              onClick={() => setActive((active + products.length + 1) % products.length)}
            >
              <ArrowRight className="size-6" />
            </button>
          </div>
        ) : null}
      </header>
      <div className="relative">
        <div
          className="override grid h-[28rem] auto-cols-[min(20rem,60vw)] grid-flow-col gap-6 overflow-x-auto pb-1 [scrollbar-width:none] lg:auto-cols-[40rem] [&::-webkit-scrollbar]:hidden"
          ref={isLoading ? null : itemsRef}
          style={{ scrollSnapType: dragStart != null ? "none" : undefined }}
          onScroll={isLoading ? undefined : handleScroll}
          onMouseDown={isLoading ? undefined : (e) => setDragStart(e.clientX)}
          onMouseMove={
            isLoading
              ? undefined
              : (e) => {
                  if (dragStart == null || !itemsRef.current) return;
                  itemsRef.current.scrollLeft -= e.movementX;
                }
          }
          onClick={
            isLoading
              ? undefined
              : (e) => {
                  if (dragStart != null && Math.abs(e.clientX - dragStart) > 30) e.preventDefault();
                  setDragStart(null);
                }
          }
          onMouseOut={isLoading ? undefined : () => setDragStart(null)}
        >
          {isLoading
            ? Array.from({ length: SKELETON_COUNT }, (_, index) => (
                <div key={index} className="flex h-full animate-pulse flex-col gap-2 transition-opacity duration-300">
                  <Skeleton className="h-4 w-1/2 shrink-0" />
                  <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded border border-border lg:flex-row">
                    <Skeleton className="aspect-video shrink-0 rounded-none lg:aspect-square lg:h-full lg:w-auto" />
                    <div className="flex flex-1 flex-col gap-3 p-4">
                      <Skeleton className="h-5 w-2/3" />
                      <Skeleton className="h-3 w-full" />
                      <Skeleton className="h-3 w-5/6" />
                      <div className="mt-auto flex items-center justify-between">
                        <Skeleton className="h-5 w-14" />
                        <Skeleton className="h-5 w-10" />
                      </div>
                    </div>
                  </div>
                </div>
              ))
            : products.map((product, idx) => (
                <div key={product.id} className="animate-in fade-in flex h-full flex-col gap-2 duration-300">
                  <p className="truncate px-1 text-sm text-muted italic" title={product.recommendation_reason}>
                    {trimReason(product.recommendation_reason)}
                  </p>
                  <div className="min-h-0 flex-1">
                    <HorizontalCard product={product} big eager={idx < 3} />
                  </div>
                </div>
              ))}
        </div>
      </div>
    </section>
  );
};
