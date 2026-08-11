import type { KeyboardEvent } from 'react'

export const pinLength = 4

export function normalizePinDigits(value: string) {
  return value.replace(/\D/g, '').slice(0, pinLength)
}

export function isCompletePin(value: string) {
  return /^\d{4}$/.test(value)
}

export function canSubmitPin({ pin, confirmPin, isPending, isSubmitting }: { pin: string; confirmPin?: string; isPending: boolean; isSubmitting: boolean }) {
  return isCompletePin(pin) && (confirmPin === undefined || isCompletePin(confirmPin)) && !isPending && !isSubmitting
}

export interface PinEntryProps {
  label: string
  value: string
  disabled?: boolean
  autoFocus?: boolean
  onChange: (value: string) => void
  onComplete?: (value: string) => void
  onEnterComplete?: () => void
}

export function PinEntry({ label, value, disabled = false, autoFocus = false, onChange, onComplete, onEnterComplete }: PinEntryProps) {
  function handleChange(nextValue: string) {
    const normalized = normalizePinDigits(nextValue)
    onChange(normalized)
    if (isCompletePin(normalized)) {
      onComplete?.(normalized)
    }
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key !== 'Enter') return
    event.preventDefault()
    if (!disabled && isCompletePin(value)) {
      onEnterComplete?.()
    }
  }

  return (
    <label>
      {label}
      <input
        inputMode="numeric"
        type="password"
        maxLength={pinLength}
        autoComplete="one-time-code"
        autoFocus={autoFocus}
        disabled={disabled}
        value={value}
        onChange={(event) => handleChange(event.target.value)}
        onKeyDown={handleKeyDown}
      />
    </label>
  )
}
