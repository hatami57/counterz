import './App.css'
import { Button } from "@/components/ui/button"
import { Badge } from './components/ui/badge'
import { useCounterStore } from './lib/store'

function App() {
    const { value } = useCounterStore()
    return (
        <>
            <div className="flex min-h-svh flex-col items-center justify-center space-y-4">
                <Badge variant="secondary" className="font-dseg7 bg-gray-800 text-green-500 text-lg" style={{ fontFamily: 'DSEG7' }}>{value}</Badge>
                <Button>Click me</Button>
            </div>
        </>
    )
}

export default App
