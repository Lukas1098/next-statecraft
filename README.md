# next-statecraft

State management skill for advanced Next.js (App Router) projects. Covers where state lives, how it's shaped, and how it interacts with rendering, caching and navigation.

## Install

```bash
npx skills@latest add lucasbernasconi/next-statecraft
```

Pick the skill, select your coding agents, done.

## What's in it

One skill: [`next-statecraft`](./skills/next-statecraft/SKILL.md). It activates whenever you're working on state in a Next.js project: choosing where state should live, designing forms, fetching server data, adding URL filters, refactoring `useEffect`s, picking a state library, debugging stale data, choosing between static and dynamic rendering, or wiring `use cache` / `revalidateTag`.

### Covered topics

- The state-location ladder (server → URL → server-state cache → store → reducer → useState)
- Anti-patterns: derived state in `useState`, redundant flags, fetch-in-effect
- Finite states with discriminated unions
- Event-driven reducers that replace cascading effects
- Forms with `FormData` + server actions + Zod
- Server state with TanStack Query (keys, hydration, mutations)
- URL state with `nuqs` and the `<Suspense key>` caveat
- Data normalization
- `useSyncExternalStore` for non-React sources
- When to reach for Zustand, Jotai, XState, Redux Toolkit
- Next.js rendering: static vs dynamic, streaming, prospective render
- `use cache` directive, page/component/function/layout semantics
- `revalidateTag`, `updateTag`, `unstable_cache` vs `use cache: remote`
- Dynamic routes and `generateStaticParams`
- App Router navigation, `<Link prefetch>`, `cacheComponents`
- Debugging, verification, and testing state

## License

MIT
