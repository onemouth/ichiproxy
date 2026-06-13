module Main where

import Network.Socket qualified as NS
import RIO

newtype TraceId = TraceId Word64
  deriving (Eq, Show)

instance Display TraceId where
  display (TraceId n) = "t=" <> display n

data Env = Env
  { envLogFunc :: LogFunc,
    envListener :: NS.Socket,
    envNextTraceId :: IORef Word64
  }

data ConnEnv = ConnEnv
  { connEnvOuter :: Env,
    connEnvTraceId :: TraceId,
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

class HasTraceId env where
  traceIdL :: Lens' env TraceId

instance HasTraceId ConnEnv where
  traceIdL = lens getter setter
    where
      getter ce = ce.connEnvTraceId
      setter ce t = ce {connEnvTraceId = t}

openListenerIO :: Int -> IO NS.Socket
openListenerIO port = do
  sock <- NS.socket NS.AF_INET NS.Stream 0
  NS.setSocketOption sock NS.ReuseAddr 1
  let addr = NS.SockAddrInet (fromIntegral port) (NS.tupleToHostAddress (127, 0, 0, 1))
  NS.bind sock addr
  NS.listen sock 5
  pure sock

handleConn :: (HasLogFunc env, HasConn env, HasPeer env, HasTraceId env) => RIO env ()
handleConn = do
  tid <- view traceIdL
  peer <- view peerL
  conn <- view connL
  logInfo (display tid <> " got connection from " <> displayShow peer)
    `finally` liftIO (NS.close conn)

acceptLoop :: RIO Env ()
acceptLoop = do
  outer <- ask
  sock <- view listenerL
  forever $ do
    (conn, peer) <- liftIO (NS.accept sock)
    tid <- liftIO $ atomicModifyIORef' outer.envNextTraceId (\n -> (n + 1, TraceId n))
    let connEnv = ConnEnv outer tid conn peer
    void $ async (runRIO connEnv handleConn)

main :: IO ()
main = do
  let port = 8080
  logOpts <- logOptionsHandle stderr True
  withLogFunc logOpts $ \lf -> do
    nextTid <- newIORef 1
    bracket (openListenerIO port) NS.close $ \sock ->
      runRIO Env {envLogFunc = lf, envListener = sock, envNextTraceId = nextTid} $ do
        logInfo $ "ichiproxy listening on 127.0.0.1:" <> display port
        acceptLoop
