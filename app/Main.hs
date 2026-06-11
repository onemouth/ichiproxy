module Main where

import RIO

data Env = Env
  { envLogFunc :: LogFunc
  }

instance HasLogFunc Env where
  logFuncL = lens getter setter
    where
      getter env = env.envLogFunc
      setter env lf = env {envLogFunc = lf}

run :: RIO Env ()
run = do
  logInfo "Hello, ichiproxy"
  logInfo "now running under my own Env"

main :: IO ()
main = do
  logOpts <-
    logOptionsHandle stderr True
  --  <&> setLogUseTime False
  withLogFunc logOpts $ \lf ->
    runRIO Env {envLogFunc = lf} run
