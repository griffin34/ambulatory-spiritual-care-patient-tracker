export function useIpc() {
  return {
    invoke: (channel, args) => window.ipc.invoke(channel, args)
  }
}
