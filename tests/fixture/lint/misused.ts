function on(listener: () => void): void {
  listener()
}

on(async () => {})
