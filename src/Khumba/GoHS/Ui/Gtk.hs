-- | The main module for the GTK+ UI, used by clients of the UI.  Also
-- implements the UI controller.
module Khumba.GoHS.Ui.Gtk ( startBoard
                          , startNewBoard
                          , startFile
                          ) where

import Control.Concurrent.MVar
import Data.IORef
import Graphics.UI.Gtk (ButtonsType(..), DialogFlags(..), MessageType(..), dialogRun, messageDialogNew, widgetDestroy)
import qualified Khumba.GoHS.Sgf as Sgf
import Khumba.GoHS.Sgf
import Khumba.GoHS.Ui.Gtk.Common
import qualified Khumba.GoHS.Ui.Gtk.MainWindow as MainWindow
import Khumba.GoHS.Ui.Gtk.MainWindow (MainWindow)

data UiCtrlImpl = UiCtrlImpl { uiModes :: IORef UiModes
                             , uiCursor :: MVar Cursor
                             , uiMainWindow :: MainWindow UiCtrlImpl
                             }

instance UiCtrl UiCtrlImpl where
  readModes = readIORef . uiModes

  modifyModes ui f = do
    newModes <- f =<< readModes ui
    writeIORef (uiModes ui) newModes
    fireViewModesChanged (uiMainWindow ui) newModes

  readCursor = readMVar . uiCursor

  isValidMove ui coord = do
    cursor <- readMVar $ uiCursor ui
    return $ Sgf.isCurrentValidMove (cursorBoard cursor) coord

  playAt ui coord = modifyMVar_ (uiCursor ui) $ \cursor ->
    if not $ Sgf.isCurrentValidMove (cursorBoard cursor) coord
    then do
      dialog <- messageDialogNew (Just $ MainWindow.myWindow $ uiMainWindow ui)
                                 [DialogModal, DialogDestroyWithParent]
                                 MessageError
                                 ButtonsOk
                                 "Illegal move."
      dialogRun dialog
      widgetDestroy dialog
      return cursor
    else case cursorChildPlayingAt coord cursor of
      Just child -> goToChild ui child >> return child
      Nothing -> do
        let board = cursorBoard cursor
            player = boardPlayerTurn board
            child = emptyNode { nodeProperties = [colorToMove player coord] }
            cursor' = cursorModifyNode (addChild child) cursor
            childCursor = cursorChild cursor' $ length (nodeChildren $ cursorNode cursor') - 1
        goReplace ui cursor'  -- TODO Don't draw twice.
        goToChild ui childCursor
        return childCursor

  goUp ui = modifyMVar (uiCursor ui) $ \cursor ->
    case cursorParent cursor of
      Nothing -> return (cursor, False)
      Just parent -> goToParent ui parent >> return (parent, True)

  goDown ui = modifyMVar (uiCursor ui) $ \cursor ->
    case cursorChildren cursor of
      child:_ -> goToChild ui child >> return (child, True)
      _ -> return (cursor, False)

  goLeft ui = modifyMVar (uiCursor ui) $ \cursor ->
    case cursorParent cursor of
      Nothing -> return (cursor, False)
      Just parentCursor ->
        let index = cursorChildIndex cursor
        in if index == 0
           then return (cursor, False)
           else let left = cursorChild parentCursor $ index - 1
                in goToLeft ui left >> return (left, True)

  goRight ui = modifyMVar (uiCursor ui) $ \cursor ->
    case cursorParent cursor of
      Nothing -> return (cursor, False)
      Just parentCursor ->
        let index = cursorChildIndex cursor
        in if index == length (nodeChildren $ cursorNode parentCursor) - 1
           then return (cursor, False)
           else let right = cursorChild parentCursor $ index + 1
                in goToRight ui right >> return (right, True)

  -- May not use the controller; it is used only for type inference.  It is
  -- called with @undefined@ in the @start@ functions below.
  openBoard _ rootNode = do
    uiRef' <- newIORef Nothing
    let uiRef = UiRef uiRef'
        cursor = rootCursor rootNode

    modesVar <- newIORef defaultUiModes
    cursorVar <- newMVar cursor
    mainWindow <- MainWindow.create uiRef

    let ui = UiCtrlImpl { uiModes = modesVar
                        , uiCursor = cursorVar
                        , uiMainWindow = mainWindow
                        }
    writeIORef uiRef' $ Just ui

    -- Do initialization that requires the 'UiCtrl' to be available.
    MainWindow.initialize mainWindow

    fireViewCursorChanged mainWindow cursor
    MainWindow.display mainWindow
    return ui

goToParent :: UiCtrlImpl -> Cursor -> IO ()
goToParent = updateUi

goToChild :: UiCtrlImpl -> Cursor -> IO ()
goToChild = updateUi

goToLeft :: UiCtrlImpl -> Cursor -> IO ()
goToLeft = updateUi

goToRight :: UiCtrlImpl -> Cursor -> IO ()
goToRight = updateUi

goReplace :: UiCtrlImpl -> Cursor -> IO ()
goReplace = updateUi

updateUi :: UiCtrlImpl -> Cursor -> IO ()
updateUi ui = fireViewCursorChanged (uiMainWindow ui)

startBoard :: Node -> IO UiCtrlImpl
startBoard = openBoard undefined

startNewBoard :: Maybe (Int, Int) -> IO UiCtrlImpl
startNewBoard = openNewBoard undefined

startFile :: String -> IO (Either String UiCtrlImpl)
startFile = openFile undefined
