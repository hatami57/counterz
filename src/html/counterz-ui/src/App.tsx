import './App.css'
import { Badge } from './components/ui/badge'
import { useCounterStore } from './lib/store'
import { useEffect, useRef, useState } from 'react'


function formatTime(seconds: number): string {
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    return [hrs, mins, secs]
        .map((v) => String(v).padStart(2, "0"))
        .join(":");
}


function App() {
    const { value } = useCounterStore()
    const [lastCount, setLastCount] = useState<Date | null>(null);
    const [elapsedSeconds, setElapsedSeconds] = useState(0);
    const intervalRef = useRef<NodeJS.Timeout | null>(null);

    useEffect(() => {
        if (!lastCount) return;

        setElapsedSeconds(0);
        if (intervalRef.current) clearInterval(intervalRef.current);

        intervalRef.current = setInterval(() => {
            setElapsedSeconds(Math.floor((Date.now() - lastCount.getTime()) / 1000));
        }, 1000);
    }, [lastCount]);

    useEffect(() => { setLastCount(new Date()) }, [value]);

    return (
        <>
            <div className="flex min-h-svh flex-col items-center justify-center space-y-2 pa-2">
                <Badge
                    variant="secondary"
                    className="font-dseg7 bg-gray-800 text-green-500 text-lg"
                    style={{ fontFamily: 'DSEG7' }}
                >
                    {value}
                </Badge>

                <Badge variant="outline" className="text-xs" style={{ fontFamily: 'DSEG7' }}>
                    {formatTime(elapsedSeconds)}
                </Badge>
            </div>
        </>
    )
}

export default App
