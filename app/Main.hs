module Main where

import RIO

main :: IO ()
main = runSimpleApp $ logInfo "Hello, ichiproxy"
