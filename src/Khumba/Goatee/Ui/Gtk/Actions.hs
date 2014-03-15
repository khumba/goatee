-- | GTK+ 'Action' definitions.
module Khumba.Goatee.Ui.Gtk.Actions (
  Actions
  , create
  , initialize
  , destruct
  , myFileNewAction
  , myFileOpenAction
  , myFileSaveAction
  , myFileSaveAsAction
  , myToolActions
  ) where

import Control.Monad
import Data.Maybe
import Graphics.UI.Gtk
import Khumba.Goatee.Common
import Khumba.Goatee.Sgf.Board
import Khumba.Goatee.Sgf.Printer
import Khumba.Goatee.Sgf.Tree
import Khumba.Goatee.Ui.Gtk.Common

data Actions = Actions { myFileNewAction :: Action
                       , myFileOpenAction :: Action
                       , myFileSaveAction :: Action
                       , myFileSaveAsAction :: Action
                       , myToolActions :: ActionGroup
                       }

create :: UiCtrl ui => UiRef ui -> IO Actions
create uiRef = do
  let tools = enumFrom minBound

  -- File actions.
  fileActions <- actionGroupNew "File"

  -- TODO Accelerators aren't working.
  fileNewAction <- actionNew "FileNew" "New file" Nothing Nothing
  actionGroupAddActionWithAccel fileActions fileNewAction $ Just "<Control>n"
  on fileNewAction actionActivated $ do
    ui <- readUiRef uiRef
    void $ openNewBoard (Just ui) Nothing

  fileOpenAction <- actionNew "FileOpen" "Open file..." Nothing Nothing
  actionGroupAddActionWithAccel fileActions fileOpenAction $ Just "<Control>o"
  on fileOpenAction actionActivated $ fileOpen uiRef

  fileSaveAsAction <- actionNew "FileSaveAs" "Save file as..." Nothing Nothing
  actionGroupAddActionWithAccel fileActions fileSaveAsAction $ Just "<Control><Shift>s"
  on fileSaveAsAction actionActivated $ fileSaveAs uiRef

  fileSaveAction <- actionNew "FileSave" "Save file" Nothing Nothing
  actionGroupAddActionWithAccel fileActions fileSaveAction $ Just "<Control>s"
  on fileSaveAction actionActivated $ fileSave uiRef

  -- Tool actions.
  toolActions <- actionGroupNew "Tools"
  actionGroupAddRadioActions toolActions
    (flip map tools $ \tool ->
      RadioActionEntry { radioActionName = show tool
                       , radioActionLabel = toolLabel tool
                       , radioActionStockId = Nothing
                       , radioActionAccelerator = Nothing
                       , radioActionTooltip = Nothing
                       , radioActionValue = fromEnum tool
                       })
    (fromEnum initialTool)
    (\radioAction -> do ui <- readUiRef uiRef
                        setTool ui =<< fmap toEnum (radioActionGetCurrentValue radioAction))

  return Actions { myFileNewAction = fileNewAction
                 , myFileOpenAction = fileOpenAction
                 , myFileSaveAction = fileSaveAction
                 , myFileSaveAsAction = fileSaveAsAction
                 , myToolActions = toolActions
                 }

initialize :: Actions -> IO ()
initialize actions =
  -- Activate 'initialTool' (requires the controller, so we can't do it in the
  -- construction phase).
  actionActivate =<<
    fmap (fromMaybe $ error $ "Could not find the initial tool " ++ show initialTool ++ ".")
         (actionGroupGetAction (myToolActions actions) $ show initialTool)

destruct :: Actions -> IO ()
destruct _ = return ()

fileOpen :: UiCtrl ui => UiRef ui -> IO ()
fileOpen uiRef = do
  ui <- readUiRef uiRef
  dialog <- fileChooserDialogNew (Just "Open a file")
                                 Nothing
                                 FileChooserActionOpen
                                 [(stockOpen, ResponseOk),
                                  (stockCancel, ResponseCancel)]
  mapM_ (fileChooserAddFilter dialog) =<< fileFiltersForSgf
  response <- dialogRun dialog
  widgetHide dialog
  when (response == ResponseOk) $ do
    maybePath <- fileChooserGetFilename dialog
    when (isJust maybePath) $ do
      let path = fromJust maybePath
      loadResult <- openFile (Just ui) path
      case loadResult of
        Left parseError -> do
          errorDialog <- messageDialogNew
                         Nothing
                         []
                         MessageError
                         ButtonsOk
                         ("Error loading " ++ path ++ ".\n\n" ++ show parseError)
          dialogRun errorDialog
          widgetDestroy errorDialog
        Right _ -> return ()
  widgetDestroy dialog

fileSaveAs :: UiCtrl ui => UiRef ui -> IO ()
fileSaveAs uiRef = do
  ui <- readUiRef uiRef
  dialog <- fileChooserDialogNew (Just "Save file")
                                 Nothing
                                 FileChooserActionSave
                                 [(stockSave, ResponseOk),
                                  (stockCancel, ResponseCancel)]
  mapM_ (fileChooserAddFilter dialog) =<< fileFiltersForSgf
  response <- dialogRun dialog
  when (response == ResponseOk) $ do
    maybePath <- fileChooserGetFilename dialog
    whenMaybe maybePath $ \path -> do
      setFilePath ui $ Just path
      fileSave uiRef

fileSave :: UiCtrl ui => UiRef ui -> IO ()
fileSave uiRef = do
  ui <- readUiRef uiRef
  cursor <- readCursor ui
  maybePath <- getFilePath ui
  case maybePath of
    Nothing -> fileSaveAs uiRef
    Just path ->
      -- TODO Exception handling when the write fails.
      -- TODO Don't just write a single tree.
      writeFile path $
        printCollection Collection { collectionTrees = [cursorNode $ cursorRoot cursor] }
