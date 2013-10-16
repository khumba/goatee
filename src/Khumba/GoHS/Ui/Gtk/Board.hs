module Khumba.GoHS.Ui.Gtk.Board where

import Control.Monad (forM_, void, when)
import Control.Monad.Trans (liftIO)
import Control.Monad.Reader (ask)
import Data.IORef
import Data.Map ((!))
import Data.Maybe
import Data.Tree (drawTree, unfoldTree)
import Graphics.Rendering.Cairo
import Graphics.UI.Gtk hiding (Color, Cursor)
import Khumba.GoHS.Common (mapTuple)
import Khumba.GoHS.Sgf
import Khumba.GoHS.Ui.Gtk.Common
import qualified Data.Map as Map

-- | If false, then the up and down keys will move toward and away
-- from the game tree root, and left and right will move between
-- siblings.  If true, these are reversed.
useHorizontalKeyNavigation :: Bool
useHorizontalKeyNavigation = True

keyNavActions :: UiCtrl a => Map.Map String (a -> IO Bool)
keyNavActions = Map.fromList $
                if useHorizontalKeyNavigation
                then [("Up", goLeft),
                      ("Down", goRight),
                      ("Left", goUp),
                      ("Right", goDown)]
                else [("Up", goUp),
                      ("Down", goDown),
                      ("Left", goLeft),
                      ("Right", goRight)]

boardBgColor = rgb 229 178 58

boardPadding :: Int
boardPadding = 8

-- | A GTK widget that renders a Go board.
--
-- @ui@ should be an instance of 'UiCtrl'.
data GtkBoard ui = GtkBoard { gtkBoardUi :: UiRef ui
                            , gtkBoardWindow :: Window
                            , gtkBoardInfoLine :: Label
                            , gtkBoardDrawingArea :: DrawingArea
                            , gtkBoardWidth :: Int
                            , gtkBoardHeight :: Int
                            }

-- | Creates a 'GtkBoard' for rendering Go boards of the given size.
gtkBoardNew :: UiCtrl ui
            => UiRef ui
            -> Int -- ^ Width
            -> Int -- ^ Height
            -> IO (GtkBoard ui)
gtkBoardNew uiRef width height = do
  let clickHandler = boardClickHandler uiRef

  window <- windowNew
  windowSetTitle window "Go"
  windowSetDefaultSize window 440 380

  -- TODO Don't quit if other windows are open.
  on window deleteEvent $ liftIO mainQuit >> return False

  on window keyPressEvent $ do
    key <- eventKeyName
    mods <- eventModifier
    let maybeAction = Map.lookup key keyNavActions
    if null mods && isJust maybeAction
      then liftIO $ void $ readUiRef uiRef >>= fromJust maybeAction
      else case key of
        -- Write a list of the current node's properties to the console.
        "t" -> liftIO $ do
          cursor <- readCursor =<< readUiRef uiRef
          print $ nodeProperties $ cursorNode cursor
        -- Draw a tree rooted at the current node to the console.
        "T" -> liftIO $ do
          cursor <- readCursor =<< readUiRef uiRef
          putStrLn $ drawTree $ flip unfoldTree (cursorNode cursor) $ \node ->
            (show $ nodeProperties node, nodeChildren node)
        _ -> return ()
    return True

  boardBox <- vBoxNew False 0
  containerAdd window boardBox

  infoLine <- labelNew Nothing
  boxPackStart boardBox infoLine PackNatural 0

  drawingArea <- drawingAreaNew
  -- TODO Enable mouse events for the DrawingArea as mentioned in the docs for
  -- Graphics.UI.Gtk.Misc.DrawingArea.  Also handle configureEvent (resizes)?
  on drawingArea exposeEvent $ liftIO $ do
    cursor <- readCursor =<< readUiRef uiRef
    drawBoard uiRef drawingArea
    return True
  boxPackStart boardBox drawingArea PackGrow 0

  return GtkBoard { gtkBoardUi = uiRef
                  , gtkBoardWindow = window
                  , gtkBoardInfoLine = infoLine
                  , gtkBoardDrawingArea = drawingArea
                  , gtkBoardWidth = width
                  , gtkBoardHeight = height
                  }

gtkBoardShow :: UiCtrl ui => GtkBoard ui -> IO ()
gtkBoardShow = widgetShowAll . gtkBoardWindow

instance UiCtrl ui => UiView (GtkBoard ui) where
  updateView cursor gtkBoard = do
    let board = cursorBoard cursor
        width = gtkBoardWidth gtkBoard
        height = gtkBoardHeight gtkBoard
    let gameInfoMsg = fromMaybe "" $ do
          let info = boardGameInfo board
          black <- gameInfoBlackName info
          white <- gameInfoWhiteName info
          let renderRank = maybe "" (\x -> " (" ++ x ++ ")")
              blackRank = renderRank $ gameInfoBlackRank info
              whiteRank = renderRank $ gameInfoWhiteRank info
          return $ white ++ whiteRank ++ " vs. " ++ black ++ blackRank ++ "\n"
        siblingMsg = case cursorParent cursor of
                     Nothing -> "Start of game."
                     Just parent ->
                       let parentChildCount = cursorChildCount parent
                       in if parentChildCount > 1
                          then "Variation " ++ show (cursorChildIndex cursor + 1)
                               ++ "/" ++ show parentChildCount ++ "."
                          else ""
        childrenMsg = let childCount = cursorChildCount cursor
                      in case childCount of
                        0 -> "End of variation."
                        1 -> ""
                        _ -> "<b>" ++ show childCount ++ " variations from here.</b>"
    labelSetMarkup (gtkBoardInfoLine gtkBoard) $
      gameInfoMsg
      ++ "Move " ++ show (boardMoveNumber board) ++ ", " ++ show (boardPlayerTurn board)
      ++ " to play.  Captures: B+" ++ show (boardBlackCaptures board) ++ ", W+"
      ++ show (boardWhiteCaptures board) ++ ".\n" ++ siblingMsg
      ++ (if siblingMsg /= [] && childrenMsg /= [] then "  " else "") ++ childrenMsg
    widgetQueueDraw $ gtkBoardDrawingArea gtkBoard

boardClickHandler :: UiCtrl a => UiRef a -> Int -> Int -> IO ()
boardClickHandler uiRef x y = do
  ui <- readUiRef uiRef
  playAt ui (x, y)

drawBoard :: UiCtrl ui => UiRef ui -> DrawingArea -> IO ()
drawBoard uiRef drawingArea = do
  ui <- readUiRef uiRef
  cursor <- readCursor ui

  (canvasWidth, canvasHeight) <- return . mapTuple fromIntegral =<< widgetGetSize drawingArea
  let board = cursorBoard cursor
      cols = fromIntegral $ boardWidth board
      rows = fromIntegral $ boardHeight board
      maxStoneWidth = canvasWidth / cols
      maxStoneHeight = canvasHeight / rows
      maxStoneLength = min maxStoneWidth maxStoneHeight

  drawWindow <- widgetGetDrawWindow drawingArea
  renderWithDrawable drawWindow $ do
    -- Set user coordinates so that the top-left stone occupies the rectangle
    -- from (0,0) to (1,1).
    when (canvasWidth > canvasHeight) $ translate ((canvasWidth - canvasHeight) / 2) 0
    when (canvasHeight > canvasWidth) $ translate 0 ((canvasHeight - canvasWidth) / 2)
    scale maxStoneLength maxStoneLength

    -- Fill the background a nice woody shade.
    setColor boardBgColor
    paint

    setSourceRGB 0 0 0
    rectangle 0.5 0.5 (cols - 1) (rows - 1)
    gridLineWidth <- fmap fst $ deviceToUserDistance 1 0
    setLineWidth gridLineWidth
    stroke

    sequence_ $ mapBoardCoords (drawCoord board) board
  return ()

drawCoord :: BoardState -> Int -> Int -> CoordState -> Render ()
drawCoord board x y coord = do
  let x' = fromIntegral x
      y' = fromIntegral y
      draw = do
        -- Draw the grid.
        let gridX0 = x' + if x == 0 then 0.5 else 0
            gridY0 = y' + if y == 0 then 0.5 else 0
            gridX1 = x' + if x == boardWidth board - 1 then 0.5 else 1
            gridY1 = y' + if y == boardHeight board - 1 then 0.5 else 1
        moveTo gridX0 gridY0
        lineTo gridX1 gridY1

        -- Draw a stone if present.
        case coordStone coord of
          Just color -> drawStone x' y' color
          Nothing -> return ()

  case coordVisibility coord of
    CoordInvisible -> return ()
    -- TODO CoordDimmed
    CoordVisible -> draw

drawStone :: Double -> Double -> Color -> Render ()
drawStone x y color = do
  arc (x + 0.5) (y + 0.5) 0.46 0 (2 * pi)
  setLineWidth 0.025
  case color of
    Black -> setSourceRGB 1 1 1
    White -> setSourceRGB 0 0 0
  strokePreserve
  case color of
    Black -> setSourceRGB 0 0 0
    White -> setSourceRGB 1 1 1
  fill

rgb r g b = (r / 255, g / 255, b / 255)

setColor (r, g, b) = setSourceRGB r g b
