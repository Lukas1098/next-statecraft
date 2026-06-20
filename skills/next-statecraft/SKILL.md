---
name: next-statecraft
description: >-
  Expert guidance for state management in advanced Next.js (App Router) projects: where state should live (server, URL, cookies, server-state cache, store, reducer, local), how to shape it (finite states, normalization, derive-don't-sync), the React 19 / Next 15 state primitives (useActionState, useOptimistic, useTransition, use(promise), useSyncExternalStore), how server mutations and cache invalidation drive client state, and how to refactor cascading useEffects into event-driven reducers. Use when modeling state, designing forms, picking a state library, wiring TanStack Query with SSR hydration, syncing state to the URL, applying optimistic updates, or debugging stale or duplicated state.
---

# next-statecraft

State management decisions that scale in advanced Next.js (App Router) projects: where state lives, how it's shaped, and which React 19 / Next 15 primitive moves it.

## When to use

Trigger on any of: deciding where new state should live, designing a form, fetching server data on the client, adding URL filters / search params, applying optimistic updates, refactoring multiple `useEffect`s, choosing or replacing a state library (Zustand, Jotai, XState, Redux, TanStack Query), wiring SSR hydration for TanStack Query, reading cookies / headers / params as server state, persisting client state across routes, or debugging stale or duplicated state.

This skill is about **state architecture**, not rendering modes, file conventions or perf rules. For those, pair with a Next.js App Router / React perf skill.

---

## 1. Decide where state lives (most important step)

Walk this ladder top-down. Stop at the first rung that fits.

| Rung | State belongs in | Use when |
|------|------------------|----------|
| 1 | **Server / DB** | Source of truth, persisted, shared across users. Read in server components. |
| 2 | **Cookies / headers** (server-readable) | Auth, theme, locale, feature flags, A/B bucket. Read with `cookies()` / `headers()` in server components. |
| 3 | **URL search params** | User-shareable, bookmarkable, survives refresh: filters, pagination, active tab, selected ID. Use `nuqs` or `useSearchParams` + `router.replace`. |
| 4 | **Server-state library cache** (TanStack Query) | Async server data on the client: lists, details, mutations, optimistic updates. Never with bare `useEffect` + `useState`. |
| 5 | **External store** (Zustand / XState Store / Jotai) | Cross-tree client state with non-trivial logic or many subscribers (cart, multi-step wizard). |
| 6 | **`useReducer` + Context** | Co-located cross-component state with clear transitions. |
| 7 | **`useState`** | Component-local UI state. Default for ephemeral. |
| — | **`useRef`** | Mutable value that should NOT trigger re-renders (timers, DOM nodes, latest-value). |

Rule of thumb: if two components read the same value, push it up one rung. If a value never reaches JSX, it isn't state — it's a ref.

---

## 2. Anti-patterns to delete on sight

**Derived state stored in `useState` + synced via `useEffect`** — derive in render instead.

```tsx
// Bad
const [total, setTotal] = useState(0);
useEffect(() => { setTotal(items.reduce((a, i) => a + i.cost, 0)); }, [items]);

// Good
const total = items.reduce((a, i) => a + i.cost, 0);
```

**Storing full objects when an ID is enough** — store the ID, look up the object.

```tsx
// Bad
const [selectedHotel, setSelectedHotel] = useState<Hotel|null>(null);

// Good
const [selectedHotelId, setSelectedHotelId] = useState<string|null>(null);
const selected = hotels.find(h => h.id === selectedHotelId);
```

**`useState` for non-render values** (timer IDs, abort controllers, latest refs) — use `useRef`.

**Multiple boolean flags representing one status** (`isLoading`, `isError`, `isSuccess`) — collapse into a discriminated union (§3).

**`useEffect` to fetch on mount + manage `isLoading`/`error`** — use TanStack Query (§6).

**Reading state inside a `useEffect` to setState in another `useEffect`** — model the transition as an event in a reducer (§4).

**Mirroring server data into `useState`** — the TanStack cache IS the store. Reading `data` from the query is the only source.

---

## 3. Make impossible states impossible (finite states)

Replace boolean soup with a tagged union.

```tsx
type State =
  | { status: 'idle';       form: Form }
  | { status: 'submitting'; form: Form }
  | { status: 'error';      form: Form; error: string }
  | { status: 'success';    data: Confirmation };
```

When to apply: any time you have 2+ booleans that overlap, or a UI with explicit modes (idle, loading, result, error). Pair with an event-driven reducer (§4).

---

## 4. Event-driven reducers (kill cascading effects)

Symptom: 3+ `useEffect`s where one sets state that triggers the next. Race conditions, dead branches, jumpy logic.

Cure: model transitions as **events**; use ONE effect driven by `state.status`.

```tsx
type Action =
  | { type: 'INPUT_CHANGED'; inputs: Inputs }
  | { type: 'FLIGHT_SELECTED'; flight: Flight }
  | { type: 'RESULTS'; flights: Flight[] }
  | { type: 'FAILED'; error: string };

function reducer(state: State, a: Action): State {
  switch (a.type) {
    case 'INPUT_CHANGED':   return { ...state, inputs: a.inputs, status: 'searchingFlights' };
    case 'FLIGHT_SELECTED': return { ...state, flight: a.flight, status: 'searchingHotels' };
    case 'RESULTS':         return { ...state, flights: a.flights, status: 'flightsReady' };
    case 'FAILED':          return { ...state, status: 'error', error: a.error };
  }
}

useEffect(() => {
  if (state.status === 'searchingFlights') {
    const ctrl = new AbortController();
    searchFlights(state.inputs, ctrl.signal).then(
      flights => dispatch({ type: 'RESULTS', flights }),
      e       => dispatch({ type: 'FAILED', error: String(e) }),
    );
    return () => ctrl.abort();
  }
}, [state.status]);
```

Think "what event caused this transition?" not "what should I do when this changed?"

---

## 5. Forms: server actions + `useActionState`

`useState` per field is rarely the right tool for mutations. Use `FormData` + server action + Zod, and treat the action's return value as state.

```tsx
// app/actions.ts
'use server';
import { z } from 'zod';

const Schema = z.object({
  firstName: z.string().min(1),
  email: z.string().email(),
  age: z.coerce.number().min(18),
});

export type SubmitState =
  | { status: 'idle' }
  | { status: 'error'; errors: Record<string, string[]> }
  | { status: 'success'; userId: string };

export async function submit(_prev: SubmitState, formData: FormData): Promise<SubmitState> {
  const parsed = Schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: 'error', errors: parsed.error.flatten().fieldErrors };
  const user = await db.user.create({ data: parsed.data });
  revalidateTag('users');
  return { status: 'success', userId: user.id };
}
```

```tsx
// component
'use client';
import { useActionState } from 'react';

const [state, action, pending] = useActionState(submit, { status: 'idle' });

<form action={action}>
  <input name="firstName" required />
  {state.status === 'error' && <Err errors={state.errors.firstName} />}
  <button disabled={pending}>{pending ? 'Saving…' : 'Save'}</button>
</form>
```

Key points:
- The action's **return value is the new state** — model it as a discriminated union (§3).
- The `prev` argument lets you implement form-level history (preserve previous input on validation error).
- The action call **carries cache invalidation** (`revalidateTag` / `updateTag`) — don't split the mutation across action + manual refetch.
- Use field-level `useState` only for **real-time** UI (live search, masked inputs, debounced filters). Same Zod schema validates client-side previews.

---

## 6. Server state: TanStack Query (with SSR hydration)

Any server data that lives on the client gets TanStack Query — never bare `useEffect`. You get caching, dedup, retries, background refetch.

### Basic query

```tsx
const { data, isLoading, error } = useQuery({
  queryKey: ['flights', { destination, departure }], // primitive shape, NOT an object reference
  queryFn: () => fetchFlights({ destination, departure }),
  staleTime: 5 * 60 * 1000,
});
```

Query-key rule: stable primitives, never an object identity that changes each render.

### SSR hydration in App Router

Prefetch on the server, serialize the cache, rehydrate on the client. The query then has data on first render — no flash.

```tsx
// app/flights/page.tsx (server component)
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query';

export default async function Page() {
  const qc = new QueryClient();
  await qc.prefetchQuery({
    queryKey: ['flights', { destination, departure }],
    queryFn: () => fetchFlights({ destination, departure }),
  });
  return (
    <HydrationBoundary state={dehydrate(qc)}>
      <FlightsClient />
    </HydrationBoundary>
  );
}
```

Use the **same `queryKey` shape** on both sides or hydration silently misses.

### Mutations

```tsx
const m = useMutation({
  mutationFn: submitBooking,
  onSuccess: () => qc.invalidateQueries({ queryKey: ['bookings'] }),
});
```

Pair invalidation with the server action's `revalidateTag` — one invalidates the client cache, the other the Next.js render cache. Both are needed.

---

## 7. Optimistic updates

Two layers, depending on where the source-of-truth lives.

### Client cache: TanStack `onMutate` + rollback

```tsx
const m = useMutation({
  mutationFn: addTodo,
  onMutate: async (newTodo) => {
    await qc.cancelQueries({ queryKey: ['todos'] });
    const prev = qc.getQueryData<Todo[]>(['todos']);
    qc.setQueryData<Todo[]>(['todos'], (old = []) => [...old, { ...newTodo, id: 'temp', pending: true }]);
    return { prev };
  },
  onError: (_e, _v, ctx) => qc.setQueryData(['todos'], ctx?.prev),
  onSettled: () => qc.invalidateQueries({ queryKey: ['todos'] }),
});
```

### Server actions: React 19 `useOptimistic`

For optimistic state that lives on the rendered list (no TanStack), use the built-in.

```tsx
'use client';
import { useOptimistic, startTransition } from 'react';

function Todos({ todos, addTodo }: { todos: Todo[]; addTodo: (text: string) => Promise<void> }) {
  const [optimistic, addOptimistic] = useOptimistic(
    todos,
    (state, text: string) => [...state, { id: 'temp', text, pending: true }],
  );

  async function action(formData: FormData) {
    const text = String(formData.get('text'));
    startTransition(() => addOptimistic(text)); // optimistic state lives only inside the transition
    await addTodo(text);
  }

  return <form action={action}>{/* render `optimistic` */}</form>;
}
```

`useOptimistic` requires the call to be inside a transition. Pair with `useActionState` when the action also returns form state.

---

## 8. URL as state (`nuqs`)

If a user might bookmark, share, or refresh into that state, it goes in the URL.

```tsx
import { useQueryState, parseAsInteger } from 'nuqs';

const [q, setQ] = useQueryState('q');
const [page, setPage] = useQueryState('page', parseAsInteger.withDefault(1));
```

Yes for: filters, search terms, pagination, active tab, selected ID, sort, view mode.
No for: dropdown open/closed, hover, transient form input mid-typing.

**Suspense + search params caveat**: a `<Suspense>` does NOT re-trigger its fallback when only search params change. Force it with `key`:

```tsx
<Suspense key={searchParams.filter} fallback={<Loading />}>
  <Table filter={searchParams.filter} />
</Suspense>
```

For setters that trigger expensive re-renders (filtering 10k rows), wrap in `startTransition` (§9) so typing stays responsive.

---

## 9. Async transitions (`useTransition` / `startTransition`)

Use when a state update triggers heavy work (filter, large URL change, server action) and you want the previous UI to stay interactive.

```tsx
const [pending, startTransition] = useTransition();

function onFilter(next: string) {
  startTransition(() => {
    setFilter(next);          // marked as non-urgent
    setQ(next);               // nuqs setter, also non-urgent
  });
}

<input onChange={e => onFilter(e.target.value)} />
{pending && <Spinner />}
```

Rule of thumb: any setter that drives a Suspense boundary, a TanStack refetch, or a URL change with downstream re-render — wrap it.

`useOptimistic` updates MUST be inside a transition (§7).

---

## 10. React 19 `use(promise)`

A way to consume a server-streamed promise as state in a client component. Lets the server start fetching and the client await without `useEffect`.

```tsx
// server
export default function Page() {
  const flightsPromise = fetchFlights();    // do NOT await
  return <FlightsClient flights={flightsPromise} />;
}

// client
'use client';
import { use, Suspense } from 'react';

function FlightsClient({ flights }: { flights: Promise<Flight[]> }) {
  const data = use(flights);                // suspends here
  return <List items={data} />;
}

// parent must provide a Suspense boundary
<Suspense fallback={<Loading />}><FlightsClient flights={flightsPromise} /></Suspense>
```

When to reach for it instead of TanStack: one-shot data that doesn't need caching, refetching, or client-side mutation. TanStack still wins for anything you'll re-read.

---

## 11. Server-side state sources: `cookies()`, `headers()`, `params`

State that lives on the request, read in server components. Don't lift it to the client just to read it.

```tsx
// app/dashboard/page.tsx
import { cookies, headers } from 'next/headers';

export default async function Page() {
  const theme = (await cookies()).get('theme')?.value ?? 'light';
  const locale = (await headers()).get('accept-language')?.split(',')[0] ?? 'en';
  const session = await getSession();        // also server-only
  return <Dashboard theme={theme} locale={locale} session={session} />;
}
```

Set cookies from a server action — that's the mutation path for this state class.

```tsx
'use server';
export async function setTheme(theme: 'light' | 'dark') {
  (await cookies()).set('theme', theme);
}
```

Use for: auth, theme, locale, feature flags, A/B bucket, anything that should be read before paint.

---

## 12. Normalize lists; don't nest entities

Nested writes are O(n·m) and bug-prone. Flatten by ID.

```tsx
// Bad (nested)
{ destinations: [{ id:'d1', todos:[{ id:'t1', text:'…' }] }] }

// Good (normalized)
{
  destinations: { d1: { id:'d1', name:'Paris' } },
  todos:        { t1: { id:'t1', text:'…', destinationId:'d1' } },
}
```

Apply when entities have independent CRUD or appear in multiple lists. Skip for tiny static structures.

---

## 13. `useSyncExternalStore` for non-React sources

Use for browser APIs, third-party stores, websockets, anything outside React's state world. Solves tearing and hydration mismatches automatically.

```tsx
const isOnline = useSyncExternalStore(
  (cb) => {
    window.addEventListener('online', cb);
    window.addEventListener('offline', cb);
    return () => {
      window.removeEventListener('online', cb);
      window.removeEventListener('offline', cb);
    };
  },
  () => navigator.onLine,
  () => true, // SSR snapshot
);
```

Not for plain React state or Context.

---

## 14. Persisting state across routes & sessions

| Need | Mechanism |
|------|-----------|
| Survives route change, lost on refresh | Zustand / Jotai store at the root client provider |
| Survives refresh, single device | `zustand/middleware` `persist` to `localStorage` |
| Survives device, requires auth | Server + DB, read via §11 |
| Shareable / deep-linkable | URL (§8) |
| Per-request server-side | Cookie (§11) |

Trap: persisting to `localStorage` on the server-rendered first paint causes hydration mismatch. Gate with a mounted flag, or hydrate from a server-read cookie.

```tsx
const useCart = create(persist<CartState>((set) => ({ /* ... */ }), { name: 'cart' }));
```

---

## 15. Picking a state library

Default to React built-ins. Add a library only when you hit a wall.

| Need | Reach for |
|------|-----------|
| Server data on the client | **TanStack Query** (always) |
| Shareable URL state | **nuqs** |
| Cross-tree client store, simple ergonomics | **Zustand** |
| Independent atoms, fine-grained subs | **Jotai** |
| Complex finite-state logic, statecharts | **XState / XState Store** |
| Mature Redux team conventions | **Redux Toolkit** |

Smell test: prop drilling beyond 2-3 levels, Context causing whole-tree re-renders, the same value mirrored in 3+ places — pull it into a store.

Never use Context for high-frequency updates (mouse, scroll) — every consumer re-renders.

---

## 16. Cache invalidation: the state-mutation contract

A server mutation usually invalidates state in two places. Both must be hit.

```tsx
'use server';
import { revalidateTag, updateTag } from 'next/cache';

export async function updateProduct(id: string, data: Patch) {
  await db.products.update(id, data);
  revalidateTag('products');       // stale-while-revalidate, serves stale now, refreshes in background
  // updateTag('products');        // immediate purge, read-your-own-writes — server actions only, NOT route handlers
}
```

- `revalidatePath` is `revalidateTag` under the hood.
- On the client, also `qc.invalidateQueries({ queryKey: ['products'] })` if TanStack is caching the same data.
- Cache freshness affects what counts as "state" for the next render — a missed invalidation looks identical to a stale state bug.

For caching internals (`use cache`, `generateStaticParams`, ISR mechanics, streaming, prefetch), use a Next.js rendering skill.

---

## 17. Debugging state

- **Stale data after mutation** → server action missing `revalidateTag` AND/OR TanStack `invalidateQueries`.
- **`<Suspense>` doesn't show its fallback on filter change** → add `key={searchParam}` (§8).
- **Re-renders on every keystroke across the whole tree** → Context mutated; move to a store with selectors.
- **Hydration mismatch on first paint** → reading `localStorage` / `window` during render. Gate with mounted flag, or hydrate from cookie (§11, §14).
- **Race condition between two requests** → unstable query key, or bare `useEffect` instead of TanStack.
- **`useOptimistic` not applying** → call is outside a transition.
- **Form state lost on validation error** → not returning `prev`-aware state from the action (§5).

---

## 18. Testing state

Test reducers, selectors, and action result shapes as pure functions. Don't render unless you must.

```tsx
test('flightSelected → hotel step', () => {
  const next = bookingReducer(
    { step: 'search', flight: null },
    { type: 'flightSelected', flight: mock },
  );
  expect(next.step).toBe('hotel');
  expect(next.flight).toBe(mock);
});

test('submit returns error state on invalid email', async () => {
  const fd = new FormData();
  fd.set('email', 'nope');
  const state = await submit({ status: 'idle' }, fd);
  expect(state.status).toBe('error');
});
```

Cover happy paths, edge cases (null, invalid ranges), invalid transitions, business rules. Integration tests stay sparse, reserved for critical user paths.

---

## Quick decision card

| Question | Answer |
|----------|--------|
| Where does this state go? | §1 ladder, top-down |
| Should I add another `useEffect`? | Probably no — model it as an event (§4) |
| How do I fetch this on the client? | TanStack Query + SSR hydration (§6) |
| Should this be in the URL? | Will the user share/refresh into it? Then yes (§8) |
| Auth / theme / locale? | Cookies + `cookies()` (§11) |
| How do I make the UI feel instant? | `useOptimistic` or TanStack `onMutate` (§7) |
| Why is my mutation stale? | Missing `revalidateTag` and/or `invalidateQueries` (§16) |
| Why does typing lag in a filter? | Wrap setter in `startTransition` (§9) |
| Why does my Suspense not show? | Missing `key` on search params (§8) |
| Should I add Zustand / Jotai / XState? | Only after Context + reducer stops scaling (§15) |
| Hydration mismatch? | Reading `localStorage` during render (§14, §17) |
