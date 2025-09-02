/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            fontFamily: {
                arabic: ["AmiriQuran"],
                dseg7: ["DSEG7"],
            }
        },
    },
    plugins: [],
}
