import { LoginForm } from '@/components/LoginForm'

export const metadata = { title: 'Aanmelden' }

export default function Page() {
  return <LoginForm brandName="PokerLeague" fallbackNext="/" />
}
