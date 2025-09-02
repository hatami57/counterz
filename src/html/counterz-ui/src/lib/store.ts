import { create } from 'zustand'

type State = {
    value: number
}

type Actions = {
    increment: (n: number) => void
    set: (n: number) => void
}

export const useCounterStore = create<State & Actions>((set) => ({
    value: 0,
    increment: (n: number) => set((state) => ({ value: state.value + n })),
    set: (n: number) => set({ value: n }),
}))

declare global {
    interface Window {
        counterStore: any;
        // setReactLoading: (loading: boolean) => void;
    }
}

window.counterStore = {
    increment(n: number) {
        useCounterStore.getState().increment(n)
    },
    set(n: number) {
        useCounterStore.getState().set(n)
    }
}
