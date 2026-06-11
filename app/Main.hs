module Main where

import RIO

data Env = Env
  { envLogFunc :: LogFunc
  , envPort :: Int
  }

instance HasLogFunc Env where
  logFuncL = lens getter setter
    where
      getter env = env.envLogFunc
      setter env lf = env {envLogFunc = lf}

class HasPort env where
  portL :: Lens' env Int

instance HasPort Env where
  portL = lens getter setter
    where
      getter env = env.envPort
      setter env p = env {envPort = p}

run :: (HasLogFunc env, HasPort env) => RIO env ()
run = do
  port <- view portL
  logInfo $ "ichiproxy starting on port " <> display port

main :: IO ()
main = do
  let port = 8080
  logOpts <- logOptionsHandle stderr True
  withLogFunc logOpts $ \lf ->
    runRIO Env {envLogFunc = lf, envPort = port} run
