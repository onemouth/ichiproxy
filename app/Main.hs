module Main where

import Network.Socket qualified as NS
import Options.Applicative.Simple
import RIO

newtype TraceId = TraceId Word64
  deriving (Eq, Show)

instance Display TraceId where
  display (TraceId n) = "t=" <> display n

data Env = Env
  { envLogFunc :: LogFunc,
    envLogOpts :: LogOptions,
    envListener :: NS.Socket,
    envNextTraceId :: IORef Word64
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

data Args = Args
  { argsHost :: NS.HostName,
    argsPort :: Int
  }

parseArgs :: Parser Args
parseArgs =
  Args
    <$> strOption
      ( long "host"
          <> short 'h'
          <> metavar "host"
          <> value "127.0.0.1"
          <> showDefault
          <> help "Address to bind on"
      )
    <*> option
      auto
      ( long "port"
          <> short 'p'
          <> metavar "port"
          <> value 8080
          <> showDefault
          <> help "Port to listen on"
      )

main :: IO ()
main = do
  (args, ()) <-
    simpleOptions
      "0.1.0.0"
      "ichiproxy"
      "HTTPS pass-through proxy"
      parseArgs
      empty
  logOpts <- setLogUseLoc True <$> logOptionsHandle stderr True
  withLogFunc logOpts $ \lf -> do
    nextTid <- newIORef 1
    bracket (openListenerIO args.argsHost args.argsPort) NS.close $ \sock ->
      runRIO Env {envLogFunc = lf, envLogOpts = logOpts, envListener = sock, envNextTraceId = nextTid} $ do
        logInfo $ "ichiproxy listening on " <> fromString args.argsHost <> ":" <> display args.argsPort
        acceptLoop
