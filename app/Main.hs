module Main where

import Ichiproxy.Env
import Ichiproxy.Net
import Network.Socket qualified as NS
import Options.Applicative.Simple
import RIO

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
