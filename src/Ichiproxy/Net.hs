module Ichiproxy.Net
  ( openListenerIO,
    acceptLoop,
  )
where

import Ichiproxy.Env
import Ichiproxy.Http
import Network.Socket qualified as NS
import Network.Socket.ByteString qualified as NSB
import RIO
import RIO.ByteString qualified as B

openListenerIO :: NS.HostName -> Int -> IO NS.Socket
openListenerIO host port = do
  let hints = NS.defaultHints {NS.addrFlags = [NS.AI_PASSIVE], NS.addrSocketType = NS.Stream}
  addr : _ <- NS.getAddrInfo (Just hints) (Just host) (Just (show port))
  sock <- NS.socket (NS.addrFamily addr) NS.Stream 0
  NS.setSocketOption sock NS.ReuseAddr 1
  NS.bind sock (NS.addrAddress addr)
  NS.listen sock 5
  pure sock

dialUpstreamIO :: NS.HostName -> Int -> IO NS.Socket
dialUpstreamIO host port = do
  let hints = NS.defaultHints {NS.addrSocketType = NS.Stream}
  addr : _ <- NS.getAddrInfo (Just hints) (Just host) (Just (show port))
  sock <- NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol
  NS.connect sock (NS.addrAddress addr)
  pure sock

-- | Copy bytes from @src@ to @dst@ until @src@ EOFs, then half-close @dst@'s
-- write side so the peer reader sees EOF. Shutdown errors are swallowed —
-- if @dst@ is already gone, there's nothing left to do.
splice :: NS.Socket -> NS.Socket -> IO ()
splice src dst = pump `finally` ignore (NS.shutdown dst NS.ShutdownSend)
  where
    pump = do
      chunk <- NSB.recv src 4096
      unless (B.null chunk) $ NSB.sendAll dst chunk >> pump
    ignore a = a `catch` \(_ :: SomeException) -> pure ()

handleConn :: (HasLogFunc env, HasConn env, HasPeer env) => RIO env ()
handleConn = do
  peer <- view peerL
  conn <- view connL
  serveClient conn peer `finally` liftIO (NS.close conn)

serveClient :: (HasLogFunc env) => NS.Socket -> NS.SockAddr -> RIO env ()
serveClient conn peer = do
  logInfo ("got connection from " <> displayShow peer)
  result <- tryAny (liftIO (readRequestHead conn))
  case result of
    Left e -> logError ("read failed: " <> displayShow e)
    Right raw -> case parseConnect raw of
      Nothing -> do
        logWarn "not a CONNECT request — rejecting"
        liftIO $ NSB.sendAll conn "HTTP/1.1 400 Bad Request\r\n\r\n"
      Just (host, port) -> tunnel conn host port

tunnel :: (HasLogFunc env) => NS.Socket -> NS.HostName -> Int -> RIO env ()
tunnel client host port = do
  logInfo ("CONNECT " <> fromString host <> ":" <> display port)
  result <- tryAny (liftIO (dialUpstreamIO host port))
  case result of
    Left e -> do
      logWarn ("upstream dial failed: " <> displayShow e)
      liftIO $ NSB.sendAll client "HTTP/1.1 502 Bad Gateway\r\n\r\n"
    Right upstream -> do
      pump upstream `finally` liftIO (NS.close upstream)
      logInfo "tunnel closed"
  where
    pump upstream = do
      liftIO $ NSB.sendAll client "HTTP/1.1 200 Connection established\r\n\r\n"
      liftIO $ concurrently_ (splice client upstream) (splice upstream client)

acceptLoop :: RIO Env ()
acceptLoop = do
  outer <- ask
  sock <- view listenerL
  forever $ do
    (conn, peer) <- liftIO (NS.accept sock)
    tid <- liftIO $ atomicModifyIORef' outer.envNextTraceId (\n -> (n + 1, TraceId n))
    let opts = setLogFormat ((display tid <> " ") <>) outer.envLogOpts
    (connLF, cleanupLF) <- liftIO $ newLogFunc opts
    let connEnv = ConnEnv (outer {envLogFunc = connLF}) conn peer
    void $ async (runRIO connEnv handleConn `finally` liftIO cleanupLF)
