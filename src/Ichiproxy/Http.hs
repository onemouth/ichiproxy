module Ichiproxy.Http
  ( parseConnect,
    readRequestHead,
  )
where

import Network.Socket qualified as NS
import Network.Socket.ByteString qualified as NSB
import RIO
import RIO.ByteString qualified as B
import RIO.Text qualified as T

-- | Read the HTTP request head — everything up to and including @\\r\\n\\r\\n@.
-- Capped at 8 KiB so a misbehaving client can't blow our memory.
readRequestHead :: NS.Socket -> IO ByteString
readRequestHead sock = go mempty
  where
    eom = "\r\n\r\n"
    limit = 8192
    go buf
      | eom `B.isInfixOf` buf = pure buf
      | B.length buf > limit = throwString "request headers too large"
      | otherwise = do
          chunk <- NSB.recv sock 4096
          if B.null chunk
            then throwString "client closed before headers complete"
            else go (buf <> chunk)

-- | Parse @CONNECT host:port HTTP/1.x@. IPv6 bracketed form is rejected
-- for v0 simplicity.
parseConnect :: ByteString -> Maybe (NS.HostName, Int)
parseConnect raw = case T.words firstLine of
  ["CONNECT", target, ver] | "HTTP/" `T.isPrefixOf` ver -> hostPort target
  _ -> Nothing
  where
    txt = decodeUtf8Lenient raw
    firstLine = T.takeWhile (/= '\r') txt
    hostPort t = case T.split (== ':') t of
      [h, p] -> (T.unpack h,) <$> readMaybe (T.unpack p)
      _ -> Nothing
