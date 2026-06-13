module Ichiproxy.Net
  ( openListenerIO,
    acceptLoop,
  )
where

import Ichiproxy.Env
import Network.Socket qualified as NS
import RIO

openListenerIO :: NS.HostName -> Int -> IO NS.Socket
openListenerIO host port = do
  let hints = NS.defaultHints {NS.addrFlags = [NS.AI_PASSIVE], NS.addrSocketType = NS.Stream}
  addr : _ <- NS.getAddrInfo (Just hints) (Just host) (Just (show port))
  sock <- NS.socket (NS.addrFamily addr) NS.Stream 0
  NS.setSocketOption sock NS.ReuseAddr 1
  NS.bind sock (NS.addrAddress addr)
  NS.listen sock 5
  pure sock

handleConn :: (HasLogFunc env, HasConn env, HasPeer env) => RIO env ()
handleConn = do
  peer <- view peerL
  conn <- view connL
  logInfo ("got connection from " <> displayShow peer)
    `finally` liftIO (NS.close conn)

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
