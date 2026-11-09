import type { Metadata } from "next"; import "./globals.css";
export const metadata:Metadata={title:"ТРИВОГА.UA — Україна поруч",description:"Персональний цифровий простір для зв’язку з Україною."};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="uk"><body>{children}</body></html>}