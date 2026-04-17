// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

export function useIpc() {
  return {
    invoke: (channel, args) => window.ipc.invoke(channel, args)
  }
}
