-- This file is part of Goatee.
--
-- Copyright 2014-2018 Bryan Gardiner
--
-- Goatee is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Goatee is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with Goatee.  If not, see <http://www.gnu.org/licenses/>.

module Main (main) where

import Control.Monad (void)
import Game.Goatee.Ui.Gtk
import Graphics.UI.Gtk (initGUI, mainGUI)

main :: IO ()
main = do
  args <- initGUI
  if null args
    then void (startNewBoard Nothing :: IO StdUiCtrlImpl)
    else do result <- startFile $ head args :: IO (Either String StdUiCtrlImpl)
            case result of
              Left msg -> print msg
              _ -> return ()
  mainGUI
