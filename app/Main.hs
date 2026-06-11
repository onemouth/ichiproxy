module Main where

import Network.Socket qualified as NS
import RIO

data Env = Env
  { envLogFunc :: LogFunc,
    envListener :: NS.Socket
  }

instance HasLogFunc Env where
  logFuncL = lens getter setter
    where
      getter env = env.envLogFunc
      setter env lf = env {envLogFunc = lf}

class HasListener env where
  listenerL :: Lens' env NS.Socket

instance HasListener Env where
  listenerL = lens getter setter
    where
      getter env = env.envListener
      setter env s = env {envListener = s}

openListenerIO :: Int -> IO NS.Socket
openListenerIO port = do
  sock <- NS.socket NS.AF_INET NS.Stream 0
  NS.setSocketOption sock NS.ReuseAddr 1
  let addr = NS.SockAddrInet (fromIntegral port) (NS.tupleToHostAddress (127, 0, 0, 1))
  NS.bind sock addr
  NS.listen sock 5
  pure sock

handleConn :: (HasLogFunc env) => NS.Socket -> NS.SockAddr -> RIO env ()
handleConn conn peer =
  logInfo ("got connection from " <> displayShow peer)
    `finally` liftIO (NS.close conn)

acceptLoop :: (HasLogFunc env, HasListener env) => RIO env ()
acceptLoop = do
  sock <- view listenerL
  forever $ do
    (conn, peer) <- liftIO (NS.accept sock)
    void $ async (handleConn conn peer)

main :: IO ()
main = do
  let port = 8080
  logOpts <- logOptionsHandle stderr True
  withLogFunc logOpts $ \lf ->
    bracket (openListenerIO port) NS.close $ \sock ->
      runRIO Env {envLogFunc = lf, envListener = sock} $ do
        logInfo $ "ichiproxy listening on 127.0.0.1:" <> display port
        acceptLoop
