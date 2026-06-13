module Main where

import Network.Socket qualified as NS
import RIO

data Env = Env
  { envLogFunc :: LogFunc,
    envListener :: NS.Socket
  }

data ConnEnv = ConnEnv
  { connEnvOuter :: Env,
    connEnvConn :: NS.Socket,
    connEnvPeer :: NS.SockAddr
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

outerL :: Lens' ConnEnv Env
outerL = lens getter setter
  where
    getter ce = ce.connEnvOuter
    setter ce e = ce {connEnvOuter = e}

instance HasLogFunc ConnEnv where
  logFuncL = outerL . logFuncL

class HasConn env where
  connL :: Lens' env NS.Socket

instance HasConn ConnEnv where
  connL = lens getter setter
    where
      getter ce = ce.connEnvConn
      setter ce s = ce {connEnvConn = s}

class HasPeer env where
  peerL :: Lens' env NS.SockAddr

instance HasPeer ConnEnv where
  peerL = lens getter setter
    where
      getter ce = ce.connEnvPeer
      setter ce p = ce {connEnvPeer = p}

openListenerIO :: Int -> IO NS.Socket
openListenerIO port = do
  sock <- NS.socket NS.AF_INET NS.Stream 0
  NS.setSocketOption sock NS.ReuseAddr 1
  let addr = NS.SockAddrInet (fromIntegral port) (NS.tupleToHostAddress (127, 0, 0, 1))
  NS.bind sock addr
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
    let connEnv = ConnEnv outer conn peer
    void $ async (runRIO connEnv handleConn)

main :: IO ()
main = do
  let port = 8080
  logOpts <- logOptionsHandle stderr True
  withLogFunc logOpts $ \lf ->
    bracket (openListenerIO port) NS.close $ \sock ->
      runRIO Env {envLogFunc = lf, envListener = sock} $ do
        logInfo $ "ichiproxy listening on 127.0.0.1:" <> display port
        acceptLoop
