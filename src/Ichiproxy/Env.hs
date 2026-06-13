module Ichiproxy.Env
  ( TraceId (..),
    Env (..),
    ConnEnv (..),
    HasListener (..),
    HasConn (..),
    HasPeer (..),
  )
where

import Network.Socket qualified as NS
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
