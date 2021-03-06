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

-- | Data structures that wrap and provide a higher-level interface to the SGF
-- game tree, including a zipper that navigates the tree and provides the
-- current board state.
module Game.Goatee.Lib.Board (
  RootInfo(..), GameInfo(..), emptyGameInfo, internalIsGameInfoNode,
  gameInfoToProperties,
  BoardState(..), boardWidth, boardHeight,
  CoordState(..), emptyBoardState, rootBoardState, emptyCoordState, boardCoordState,
  boardCoordModify, mapBoardCoords,
  isValidMove, isCurrentValidMove,
  Cursor, cursorParent, cursorChildIndex, cursorNode, cursorBoard,
  rootCursor, cursorRoot, cursorChild, cursorChildren,
  cursorChildCount, cursorChildPlayingAt, cursorProperties,
  cursorModifyNode,
  cursorVariations,
  moveToProperty,
  ) where

import Control.Monad (unless, when)
import Control.Monad.Writer (execWriter, tell)
import Data.List (find, intercalate, nub)
import Data.Maybe (fromMaybe, isJust, isNothing)
import qualified Data.Set as Set
import Game.Goatee.Common
import Game.Goatee.Lib.Property
import Game.Goatee.Lib.Tree
import Game.Goatee.Lib.Types

-- TODO Stop using errors everywhere, they're not testable.

-- | Properties that are specified in the root nodes of game trees.
data RootInfo = RootInfo
  { rootInfoWidth :: Int
  , rootInfoHeight :: Int
  , rootInfoVariationMode :: VariationMode
  } deriving (Eq, Show)

-- | Properties that are specified in game info nodes.
data GameInfo = GameInfo
  { gameInfoRootInfo :: RootInfo

  , gameInfoBlackName :: Maybe SimpleText
  , gameInfoBlackTeamName :: Maybe SimpleText
  , gameInfoBlackRank :: Maybe SimpleText

  , gameInfoWhiteName :: Maybe SimpleText
  , gameInfoWhiteTeamName :: Maybe SimpleText
  , gameInfoWhiteRank :: Maybe SimpleText

  , gameInfoRuleset :: Maybe Ruleset
  , gameInfoBasicTimeSeconds :: Maybe RealValue
  , gameInfoOvertime :: Maybe SimpleText
  , gameInfoResult :: Maybe GameResult

  , gameInfoGameName :: Maybe SimpleText
  , gameInfoGameComment :: Maybe Text
  , gameInfoOpeningComment :: Maybe SimpleText

  , gameInfoEvent :: Maybe SimpleText
  , gameInfoRound :: Maybe SimpleText
  , gameInfoPlace :: Maybe SimpleText
  , gameInfoDatesPlayed :: Maybe SimpleText
  , gameInfoSource :: Maybe SimpleText
  , gameInfoCopyright :: Maybe SimpleText

  , gameInfoAnnotatorName :: Maybe SimpleText
  , gameInfoEntererName :: Maybe SimpleText
  } deriving (Show)

-- | Builds a 'GameInfo' with the given 'RootInfo' and no extra data.
emptyGameInfo :: RootInfo -> GameInfo
emptyGameInfo rootInfo = GameInfo
  { gameInfoRootInfo = rootInfo

  , gameInfoBlackName = Nothing
  , gameInfoBlackTeamName = Nothing
  , gameInfoBlackRank = Nothing

  , gameInfoWhiteName = Nothing
  , gameInfoWhiteTeamName = Nothing
  , gameInfoWhiteRank = Nothing

  , gameInfoRuleset = Nothing
  , gameInfoBasicTimeSeconds = Nothing
  , gameInfoOvertime = Nothing
  , gameInfoResult = Nothing

  , gameInfoGameName = Nothing
  , gameInfoGameComment = Nothing
  , gameInfoOpeningComment = Nothing

  , gameInfoEvent = Nothing
  , gameInfoRound = Nothing
  , gameInfoPlace = Nothing
  , gameInfoDatesPlayed = Nothing
  , gameInfoSource = Nothing
  , gameInfoCopyright = Nothing

  , gameInfoAnnotatorName = Nothing
  , gameInfoEntererName = Nothing
  }

-- | Returns whether a node contains any game info properties.
internalIsGameInfoNode :: Node -> Bool
internalIsGameInfoNode = any ((GameInfoProperty ==) . propertyType) . nodeProperties

-- | Converts a 'GameInfo' into a list of 'Property's that can be used to
-- reconstruct the 'GameInfo'.
gameInfoToProperties :: GameInfo -> [Property]
gameInfoToProperties info = execWriter $ do
  copy PB gameInfoBlackName
  copy BT gameInfoBlackTeamName
  copy BR gameInfoBlackRank

  copy PW gameInfoWhiteName
  copy WT gameInfoWhiteTeamName
  copy WR gameInfoWhiteRank

  copy RU gameInfoRuleset
  copy TM gameInfoBasicTimeSeconds
  copy OT gameInfoOvertime
  copy RE gameInfoResult

  copy GN gameInfoGameName
  copy GC gameInfoGameComment
  copy ON gameInfoOpeningComment

  copy EV gameInfoEvent
  copy RO gameInfoRound
  copy PC gameInfoPlace
  copy DT gameInfoDatesPlayed
  copy SO gameInfoSource
  copy CP gameInfoCopyright

  copy AN gameInfoAnnotatorName
  copy US gameInfoEntererName
  where copy ctor accessor = whenMaybe (accessor info) $ \x -> tell [ctor x]

-- | An object that corresponds to a node in some game tree, and represents the
-- state of the game at that node, including board position, player turn and
-- captures, and also board annotations.
data BoardState = BoardState
  { boardCoordStates :: [[CoordState]]
    -- ^ The state of individual points on the board.  Stored in row-major order.
    -- Point @(x, y)@ can be accessed via @!! y !! x@ (but prefer
    -- 'boardCoordState').
  , boardHasInvisible :: Bool
    -- ^ Whether any of the board's 'CoordState's are invisible.  This is an
    -- optimization to make it more efficient to set the board to "all visible."
  , boardHasDimmed :: Bool
    -- ^ Whether any of the board's 'CoordState's are dimmed.  This is an
    -- optimization to make it more efficient to clear all dimming from the
    -- board.
  , boardHasCoordMarks :: Bool
    -- ^ Whether any of the board's 'CoordState's have a 'Mark' set on them.
    -- This is an optimization to make it more efficient to clear marks in the
    -- common case where there are no marks set.
  , boardArrows :: ArrowList
  , boardLines :: LineList
  , boardLabels :: LabelList
  , boardMoveNumber :: Integer
  , boardPlayerTurn :: Color
  , boardBlackCaptures :: Int
  , boardWhiteCaptures :: Int
  , boardGameInfo :: GameInfo
  }

instance Show BoardState where
  show board = concat $ execWriter $ do
    tell ["Board: (Move ", show (boardMoveNumber board),
          ", ", show (boardPlayerTurn board), "'s turn, B:",
          show (boardBlackCaptures board), ", W:",
          show (boardWhiteCaptures board), ")\n"]
    tell [intercalate "\n" $ flip map (boardCoordStates board) $
          \row -> unwords $ map show row]

    let arrows = boardArrows board
    let lines = boardLines board
    let labels = boardLabels board
    unless (null arrows) $ tell ["\nArrows: ", show arrows]
    unless (null lines) $ tell ["\nLines: ", show lines]
    unless (null labels) $ tell ["\nLabels: ", show labels]

-- | Returns the width of the board, in stones.
boardWidth :: BoardState -> Int
boardWidth = rootInfoWidth . gameInfoRootInfo . boardGameInfo

-- | Returns the height of the board, in stones.
boardHeight :: BoardState -> Int
boardHeight = rootInfoHeight . gameInfoRootInfo . boardGameInfo

-- | Used by 'BoardState' to represent the state of a single point on the board.
-- Records whether a stone is present, as well as annotations and visibility
-- properties.
data CoordState = CoordState
  { coordStar :: Bool
    -- ^ Whether this point is a star point.
  , coordStone :: Maybe Color
  , coordMark :: Maybe Mark
  , coordVisible :: Bool
  , coordDimmed :: Bool
  } deriving (Eq)

instance Show CoordState where
  show c = if not $ coordVisible c
           then "--"
           else let stoneChar = case coordStone c of
                      Nothing -> if coordStar c then '*' else '\''
                      Just Black -> 'X'
                      Just White -> 'O'
                    markChar = case coordMark c of
                      Nothing -> ' '
                      Just MarkCircle -> 'o'
                      Just MarkSquare -> 's'
                      Just MarkTriangle -> 'v'
                      Just MarkX -> 'x'
                      Just MarkSelected -> '!'
                in [stoneChar, markChar]

-- | Creates a 'BoardState' for an empty board of the given width and height.
emptyBoardState :: Int -> Int -> BoardState
emptyBoardState width height = BoardState
  { boardCoordStates = coords
  , boardHasInvisible = False
  , boardHasDimmed = False
  , boardHasCoordMarks = False
  , boardArrows = []
  , boardLines = []
  , boardLabels = []
  , boardMoveNumber = 0
  , boardPlayerTurn = Black
  , boardBlackCaptures = 0
  , boardWhiteCaptures = 0
  , boardGameInfo = emptyGameInfo rootInfo
  }
  where rootInfo = RootInfo { rootInfoWidth = width
                            , rootInfoHeight = height
                            , rootInfoVariationMode = defaultVariationMode
                            }
        starCoordState = emptyCoordState { coordStar = True }
        isStarPoint' = isStarPoint width height
        coords = map (\y -> map (\x -> if isStarPoint' x y then starCoordState else emptyCoordState)
                                [0..width-1])
                     [0..height-1]

-- Initializes a 'BoardState' from the properties on a given root 'Node'.
rootBoardState :: Node -> BoardState
rootBoardState rootNode =
  foldr applyProperty
        (emptyBoardState width height)
        (nodeProperties rootNode)
  where SZ width height = fromMaybe (SZ boardSizeDefault boardSizeDefault) $
                          findProperty propertySZ rootNode

-- | A 'CoordState' for an empty point on the board.
emptyCoordState :: CoordState
emptyCoordState = CoordState
  { coordStar = False
  , coordStone = Nothing
  , coordMark = Nothing
  , coordVisible = True
  , coordDimmed = False
  }

-- | Returns the 'CoordState' for a coordinate on a board.
boardCoordState :: Coord -> BoardState -> CoordState
boardCoordState (x, y) board = boardCoordStates board !! y !! x

-- | Modifies a 'BoardState' by updating the 'CoordState' at a single point.
boardCoordModify :: BoardState -> Coord -> (CoordState -> CoordState) -> BoardState
boardCoordModify board (x, y) f =
  board { boardCoordStates =
          listUpdate (listUpdate f x) y $ boardCoordStates board
        }

-- | Maps a function over each 'CoordState' in a 'BoardState', returning a
-- list-of-lists with the function's values.  The function is called like @fn y
-- x coordState@.
mapBoardCoords :: (Int -> Int -> CoordState -> a) -> BoardState -> [[a]]
mapBoardCoords fn board =
  zipWith applyRow [0..] $ boardCoordStates board
  where applyRow y = zipWith (fn y) [0..]

-- | Applies a function to update the 'RootInfo' within the 'GameInfo' of a
-- 'BoardState'.
updateRootInfo :: (RootInfo -> RootInfo) -> BoardState -> BoardState
updateRootInfo fn board = flip updateBoardInfo board $ \gameInfo ->
  gameInfo { gameInfoRootInfo = fn $ gameInfoRootInfo gameInfo }

-- | Applies a function to update the 'GameInfo' of a 'BoardState'.
updateBoardInfo :: (GameInfo -> GameInfo) -> BoardState -> BoardState
updateBoardInfo fn board = board { boardGameInfo = fn $ boardGameInfo board }

-- | Given a 'BoardState' for a parent node, and a child node, this function
-- constructs the 'BoardState' for the child node.
boardChild :: BoardState -> Node -> BoardState
boardChild =
  -- This function first prepares the board (clearing temporary marks, etc.)
  -- then applies the child node's properties to the board.  It is done in two
  -- stages because various points in this module apply the steps themselves.
  boardApplyChild . boardResetForChild

-- | Performs necessary updates to a 'BoardState' between nodes in the tree.
-- Clears marks.   This is the first step of 'boardChild'.
boardResetForChild :: BoardState -> BoardState
boardResetForChild board =
  board { boardCoordStates =
            (if boardHasCoordMarks board then map (map clearMark) else id) $
            boardCoordStates board
        , boardHasCoordMarks = False
        , boardArrows = []
        , boardLines = []
        , boardLabels = []
        }
  where clearMark coord = case coordMark coord of
          Nothing -> coord
          Just _ -> coord { coordMark = Nothing }

-- | Applies a child node's properties to a prepared 'BoardState'.  This is the
-- second step of 'boardChild'.
boardApplyChild :: BoardState -> Node -> BoardState
boardApplyChild = flip applyProperties

-- | Sets all points on a board to be visible (if given true) or invisible (if
-- given false).
setBoardVisible :: Bool -> BoardState -> BoardState
setBoardVisible visible board =
  if visible
  then if boardHasInvisible board
       then board { boardCoordStates = map (map $ setVisible True) $ boardCoordStates board
                  , boardHasInvisible = False
                  }
       else board
  else board { boardCoordStates = map (map $ setVisible False) $ boardCoordStates board
             , boardHasInvisible = True
             }
  where setVisible vis coord = coord { coordVisible = vis }

-- | Resets all points on a board not to be dimmed.
clearBoardDimmed :: BoardState -> BoardState
clearBoardDimmed board =
  if boardHasDimmed board
  then board { boardCoordStates = map (map clearDim) $ boardCoordStates board
             , boardHasDimmed = False
             }
  else board
  where clearDim coord = coord { coordDimmed = False }

-- | Applies a property to a 'BoardState'.  This function covers all properties
-- that modify 'BoardState's, including making moves, adding markup, and so on.
applyProperty :: Property -> BoardState -> BoardState

applyProperty (B maybeXy) board = updateBoardForMove Black $ case maybeXy of
  Nothing -> board  -- Pass.
  Just xy -> getApplyMoveResult board $
             applyMove playTheDarnMoveGoParams Black xy board
applyProperty KO board = board
applyProperty (MN moveNum) board = board { boardMoveNumber = moveNum }
applyProperty (W maybeXy) board = updateBoardForMove White $ case maybeXy of
  Nothing -> board  -- Pass.
  Just xy -> getApplyMoveResult board $
             applyMove playTheDarnMoveGoParams White xy board

applyProperty (AB coords) board =
  updateCoordStates' (\state -> state { coordStone = Just Black }) coords board
applyProperty (AW coords) board =
  updateCoordStates' (\state -> state { coordStone = Just White }) coords board
applyProperty (AE coords) board =
  updateCoordStates' (\state -> state { coordStone = Nothing }) coords board
applyProperty (PL color) board = board { boardPlayerTurn = color }

applyProperty (C {}) board = board
applyProperty (DM {}) board = board
applyProperty (GB {}) board = board
applyProperty (GW {}) board = board
applyProperty (HO {}) board = board
applyProperty (N {}) board = board
applyProperty (UC {}) board = board
applyProperty (V {}) board = board

applyProperty (BM {}) board = board
applyProperty (DO {}) board = board
applyProperty (IT {}) board = board
applyProperty (TE {}) board = board

applyProperty (AR arrows) board = board { boardArrows = arrows ++ boardArrows board }
applyProperty (CR coords) board =
  updateCoordStates' (\state -> state { coordMark = Just MarkCircle }) coords
  board { boardHasCoordMarks = True }
applyProperty (DD coords) board =
  let coords' = expandCoordList coords
      board' = clearBoardDimmed board
  in if null coords'
     then board'
     else updateCoordStates (\state -> state { coordDimmed = True }) coords'
          board' { boardHasDimmed = True }
applyProperty (LB labels) board = board { boardLabels = labels ++ boardLabels board }
applyProperty (LN lines) board = board { boardLines = lines ++ boardLines board }
applyProperty (MA coords) board =
  updateCoordStates' (\state -> state { coordMark = Just MarkX }) coords
  board { boardHasCoordMarks = True }
applyProperty (SL coords) board =
  updateCoordStates' (\state -> state { coordMark = Just MarkSelected }) coords
  board { boardHasCoordMarks = True }
applyProperty (SQ coords) board =
  updateCoordStates' (\state -> state { coordMark = Just MarkSquare }) coords
  board { boardHasCoordMarks = True }
applyProperty (TR coords) board =
  updateCoordStates' (\state -> state { coordMark = Just MarkTriangle }) coords
  board { boardHasCoordMarks = True }

applyProperty (AP {}) board = board
applyProperty (CA {}) board = board
applyProperty (FF {}) board = board
applyProperty (GM {}) board = board
applyProperty (ST variationMode) board =
  updateRootInfo (\info -> info { rootInfoVariationMode = variationMode }) board
applyProperty (SZ {}) board = board

applyProperty (AN str) board =
  updateBoardInfo (\info -> info { gameInfoAnnotatorName = Just str }) board
applyProperty (BR str) board =
  updateBoardInfo (\info -> info { gameInfoBlackRank = Just str }) board
applyProperty (BT str) board =
  updateBoardInfo (\info -> info { gameInfoBlackTeamName = Just str }) board
applyProperty (CP str) board =
  updateBoardInfo (\info -> info { gameInfoCopyright = Just str }) board
applyProperty (DT str) board =
  updateBoardInfo (\info -> info { gameInfoDatesPlayed = Just str }) board
applyProperty (EV str) board =
  updateBoardInfo (\info -> info { gameInfoEvent = Just str }) board
applyProperty (GC str) board =
  updateBoardInfo (\info -> info { gameInfoGameComment = Just str }) board
applyProperty (GN str) board =
  updateBoardInfo (\info -> info { gameInfoGameName = Just str }) board
applyProperty (ON str) board =
  updateBoardInfo (\info -> info { gameInfoOpeningComment = Just str }) board
applyProperty (OT str) board =
  updateBoardInfo (\info -> info { gameInfoOvertime = Just str }) board
applyProperty (PB str) board =
  updateBoardInfo (\info -> info { gameInfoBlackName = Just str }) board
applyProperty (PC str) board =
  updateBoardInfo (\info -> info { gameInfoPlace = Just str }) board
applyProperty (PW str) board =
  updateBoardInfo (\info -> info { gameInfoWhiteName = Just str }) board
applyProperty (RE result) board =
  updateBoardInfo (\info -> info { gameInfoResult = Just result }) board
applyProperty (RO str) board =
  updateBoardInfo (\info -> info { gameInfoRound = Just str }) board
applyProperty (RU ruleset) board =
  updateBoardInfo (\info -> info { gameInfoRuleset = Just ruleset }) board
applyProperty (SO str) board =
  updateBoardInfo (\info -> info { gameInfoSource = Just str }) board
applyProperty (TM seconds) board =
  updateBoardInfo (\info -> info { gameInfoBasicTimeSeconds = Just seconds }) board
applyProperty (US str) board =
  updateBoardInfo (\info -> info { gameInfoEntererName = Just str }) board
applyProperty (WR str) board =
  updateBoardInfo (\info -> info { gameInfoWhiteRank = Just str }) board
applyProperty (WT str) board =
  updateBoardInfo (\info -> info { gameInfoWhiteTeamName = Just str }) board

applyProperty (BL {}) board = board
applyProperty (OB {}) board = board
applyProperty (OW {}) board = board
applyProperty (WL {}) board = board

applyProperty (VW coords) board =
  let coords' = expandCoordList coords
  in if null coords'
     then setBoardVisible True board
     else updateCoordStates (\state -> state { coordVisible = True }) coords' $
          setBoardVisible False board

applyProperty (HA {}) board = board
applyProperty (KM {}) board = board
applyProperty (TB {}) board = board
applyProperty (TW {}) board = board

applyProperty (UnknownProperty {}) board = board

applyProperties :: Node -> BoardState -> BoardState
applyProperties node board = foldr applyProperty board (nodeProperties node)

-- | Applies the transformation function to all of a board's coordinates
-- referred to by the 'CoordList'.
updateCoordStates :: (CoordState -> CoordState) -> [Coord] -> BoardState -> BoardState
updateCoordStates fn coords board =
  board { boardCoordStates = foldr applyFn (boardCoordStates board) coords }
  where applyFn (x, y) = listUpdate (updateRow x) y
        updateRow = listUpdate fn

updateCoordStates' :: (CoordState -> CoordState) -> CoordList -> BoardState -> BoardState
updateCoordStates' fn coords = updateCoordStates fn (expandCoordList coords)

-- | Updates properties of a 'BoardState' given that the player of the given
-- color has just made a move.  Increments the move number and updates the
-- player turn.
updateBoardForMove :: Color -> BoardState -> BoardState
updateBoardForMove movedPlayer board =
  board { boardMoveNumber = boardMoveNumber board + 1
        , boardPlayerTurn = cnot movedPlayer
        }

-- | A structure that configures how 'applyMove' should handle moves that are
-- normally illegal in Go.
data ApplyMoveParams = ApplyMoveParams
  { allowSuicide :: Bool
    -- ^ If false, suicide will cause 'applyMove' to return
    -- 'ApplyMoveSuicideError'.  If true, suicide will kill the
    -- friendly group and give points to the opponent.
  , allowOverwrite :: Bool
    -- ^ If false, playing on an occupied point will cause
    -- 'applyMove' to return 'ApplyMoveOverwriteError' with the
    -- color of the stone occupying the point.  If true,
    -- playing on an occupied point will overwrite the point
    -- (the previous stone vanishes), then capture rules are
    -- applied as normal.
  } deriving (Show)

-- | As an argument to 'applyMove', causes illegal moves to be treated as
-- errors.
standardGoMoveParams :: ApplyMoveParams
standardGoMoveParams = ApplyMoveParams
  { allowSuicide = False
  , allowOverwrite = False
  }

-- | As an argument to 'applyMove', causes illegal moves to be played
-- unconditionally.
playTheDarnMoveGoParams :: ApplyMoveParams
playTheDarnMoveGoParams = ApplyMoveParams
  { allowSuicide = True
  , allowOverwrite = True
  }

-- | The possible results from 'applyMove'.
data ApplyMoveResult =
  ApplyMoveOk BoardState
  -- ^ The move was accepted; playing it resulted in the given board without
  -- capture.
  | ApplyMoveCapture BoardState Color Int
    -- ^ The move was accepted; playing it resulted in the given board with a
    -- capture.  The specified side gained the number of points given.
  | ApplyMoveSuicideError
    -- ^ Playing the move would result in suicide, which is forbidden.
  | ApplyMoveOverwriteError Color
    -- ^ There is already a stone of the specified color on the target point,
    -- and overwriting is forbidden.

-- | If the 'ApplyMoveResult' represents a successful move, then the resulting
-- 'BoardState' is returned, otherwise, the default 'BoardState' given is
-- returned.
getApplyMoveResult :: BoardState -> ApplyMoveResult -> BoardState
getApplyMoveResult defaultBoard result = fromMaybe defaultBoard $ getApplyMoveResult' result

getApplyMoveResult' :: ApplyMoveResult -> Maybe BoardState
getApplyMoveResult' result = case result of
  ApplyMoveOk board -> Just board
  ApplyMoveCapture board color points -> Just $ case color of
    Black -> board { boardBlackCaptures = boardBlackCaptures board + points }
    White -> board { boardWhiteCaptures = boardWhiteCaptures board + points }
  ApplyMoveSuicideError -> Nothing
  ApplyMoveOverwriteError _ -> Nothing

-- | Internal data structure, only for move application code.  Represents a
-- group of stones.
data ApplyMoveGroup = ApplyMoveGroup
  { applyMoveGroupOrigin :: Coord
  , applyMoveGroupCoords :: [Coord]
  , applyMoveGroupLiberties :: Int
  } deriving (Show)

-- | Places a stone of a color at a point on a board, and runs move validation
-- and capturing logic according to the given parameters.  Returns whether the
-- move was successful, and the result if so.
applyMove :: ApplyMoveParams -> Color -> Coord -> BoardState -> ApplyMoveResult
applyMove params color xy board =
  let currentStone = coordStone $ boardCoordState xy board
  in case currentStone of
    Just color -> if allowOverwrite params
                  then moveResult
                  else ApplyMoveOverwriteError color
    Nothing -> moveResult
  where boardWithMove = updateCoordStates (\state -> state { coordStone = Just color })
                                          [xy]
                                          board
        (boardWithCaptures, points) = foldr (maybeCapture $ cnot color)
                                            (boardWithMove, 0)
                                            (adjacentPoints boardWithMove xy)
        playedGroup = computeGroup boardWithCaptures xy
        moveResult
          | applyMoveGroupLiberties playedGroup == 0 =
            if points /= 0
            then error "Cannot commit suicide and capture at the same time."
            else if allowSuicide params
                 then let (boardWithSuicide, suicidePoints) =
                            applyMoveCapture (boardWithCaptures, 0) playedGroup
                      in ApplyMoveCapture boardWithSuicide (cnot color) suicidePoints
                 else ApplyMoveSuicideError
          | points /= 0 = ApplyMoveCapture boardWithCaptures color points
          | otherwise = ApplyMoveOk boardWithCaptures

-- | Capture if there is a liberty-less group of a color at a point on
-- a board.  Removes captured stones from the board and accumulates
-- points for captured stones.
maybeCapture :: Color -> Coord -> (BoardState, Int) -> (BoardState, Int)
maybeCapture color xy result@(board, _) =
  if coordStone (boardCoordState xy board) /= Just color
  then result
  else let group = computeGroup board xy
       in if applyMoveGroupLiberties group /= 0
          then result
          else applyMoveCapture result group

computeGroup :: BoardState -> Coord -> ApplyMoveGroup
computeGroup board xy =
  if isNothing (coordStone $ boardCoordState xy board)
  then error "computeGroup called on an empty point."
  else let groupCoords = bucketFill board xy
       in ApplyMoveGroup { applyMoveGroupOrigin = xy
                         , applyMoveGroupCoords = groupCoords
                         , applyMoveGroupLiberties = getLibertiesOfGroup board groupCoords
                         }

applyMoveCapture :: (BoardState, Int) -> ApplyMoveGroup -> (BoardState, Int)
applyMoveCapture (board, points) group =
  (updateCoordStates (\state -> state { coordStone = Nothing })
                     (applyMoveGroupCoords group)
                     board,
   points + length (applyMoveGroupCoords group))

-- | Returns a list of the four coordinates that are adjacent to the
-- given coordinate on the board, excluding coordinates that are out
-- of bounds.
adjacentPoints :: BoardState -> Coord -> [Coord]
adjacentPoints board (x, y) = execWriter $ do
  when (x > 0) $ tell [(x - 1, y)]
  when (y > 0) $ tell [(x, y - 1)]
  when (x < boardWidth board - 1) $ tell [(x + 1, y)]
  when (y < boardHeight board - 1) $ tell [(x, y + 1)]

-- | Takes a list of coordinates that comprise a group (e.g. a list
-- returned from 'bucketFill') and returns the number of liberties the
-- group has.  Does no error checking to ensure that the list refers
-- to a single or maximal group.
getLibertiesOfGroup :: BoardState -> [Coord] -> Int
getLibertiesOfGroup board groupCoords =
  length $ nub $ concatMap findLiberties groupCoords
  where findLiberties xy = filter (\xy' -> isNothing $ coordStone $ boardCoordState xy' board)
                                  (adjacentPoints board xy)

-- | Expands a single coordinate on a board into a list of all the
-- coordinates connected to it by some continuous path of stones of
-- the same color (or empty spaces).
bucketFill :: BoardState -> Coord -> [Coord]
bucketFill board xy0 = bucketFill' Set.empty [xy0]
  where bucketFill' known [] = Set.toList known
        bucketFill' known (xy:xys) =
          if Set.member xy known
          then bucketFill' known xys
          else let new = filter ((stone0 ==) . coordStone . flip boardCoordState board)
                                (adjacentPoints board xy)
               in bucketFill' (Set.insert xy known) (new ++ xys)
        stone0 = coordStone $ boardCoordState xy0 board

-- | Returns whether it is legal to place a stone of the given color at a point
-- on a board.  Accepts out-of-bound coordinates and returns false.
isValidMove :: BoardState -> Color -> Coord -> Bool
-- TODO Should out-of-bound coordinates be accepted?
isValidMove board color coord@(x, y) =
  let w = boardWidth board
      h = boardHeight board
  in x >= 0 && y >= 0 && x < w && y < h &&
     isJust (getApplyMoveResult' $ applyMove standardGoMoveParams color coord board)

-- | Returns whether it is legal for the current player to place a stone at a
-- point on a board.  Accepts out-of-bound coordinates and returns false.
isCurrentValidMove :: BoardState -> Coord -> Bool
isCurrentValidMove board = isValidMove board (boardPlayerTurn board)

-- | A pointer to a node in a game tree that also holds information
-- about the current state of the game at that node.
data Cursor = Cursor
  { cursorParent' :: Maybe Cursor
    -- ^ The cursor of the parent node in the tree.  This is the cursor that was
    -- used to construct this cursor.  For a root node, this is @Nothing@.
    --
    -- If this cursor's node is modified (with 'cursorModifyNode'), then this
    -- parent cursor (if present) is /not/ updated to have the modified current
    -- node as a child; the public 'cursorParent' takes care of this.

  , cursorChildIndex :: Int
    -- ^ The index of this cursor's node in its parent's child list.  When the
    -- cursor's node has no parent, the value in this field is not specified.

  , cursorNode' :: CursorNode
    -- ^ The game tree node about which the cursor stores information.  The
    -- 'CursorNode' keeps track of whether the current node has been modified
    -- since last visiting the cursor's parent (if it exists; if it doesn't,
    -- then the current node is never considered modified, although in this case
    -- it doesn't matter).  'cursorNode' is the public export.

  , cursorBoard :: BoardState
    -- ^ The complete board state for the current node.
  } deriving (Show) -- TODO Better Show Cursor instance.

-- | Keeps track of a cursor's node.  Also records whether the node has been
-- modified, and uses separate data constructors to force consideration of this.
data CursorNode =
  UnmodifiedNode { getCursorNode :: Node }
  | ModifiedNode { getCursorNode :: Node }
  deriving (Show)

-- | The cursor for the node above this cursor's node in the game tree.  The
-- node of the parent cursor is the parent of the cursor's node.
--
-- This is @Nothing@ iff the cursor's node has no parent.
cursorParent :: Cursor -> Maybe Cursor
cursorParent cursor = case cursorParent' cursor of
  Nothing -> Nothing
  p@(Just parent) -> case cursorNode' cursor of
    -- If the current node hasn't been modified, then 'parent' is still the
    -- correct parent cursor for the current node.
    UnmodifiedNode _ -> p
    -- If the current node /has/ been modified, then we need to update the
    -- parent node's child list to include the modified node rather than the
    -- original.  We do this one step at a time whenever we walk up the tree.
    ModifiedNode node ->
      Just $ flip cursorModifyNode parent $ \pnode ->
      pnode { nodeChildren = listUpdate (const node) (cursorChildIndex cursor) $
                             nodeChildren pnode }

-- | The game tree node about which the cursor stores information.
cursorNode :: Cursor -> Node
cursorNode = getCursorNode . cursorNode'

-- | Returns a cursor for a root node.
rootCursor :: Node -> Cursor
rootCursor node =
  Cursor { cursorParent' = Nothing
         , cursorChildIndex = -1
         , cursorNode' = UnmodifiedNode node
         , cursorBoard = rootBoardState node
         }

cursorRoot :: Cursor -> Cursor
cursorRoot cursor = case cursorParent cursor of
  Nothing -> cursor
  Just parent -> cursorRoot parent

cursorChild :: Cursor -> Int -> Cursor
cursorChild cursor index =
  Cursor { cursorParent' = Just cursor
         , cursorChildIndex = index
         , cursorNode' = UnmodifiedNode child
         , cursorBoard = boardChild (cursorBoard cursor) child
         }
  -- TODO Better handling or messaging for out-of-bounds:
  where child = (!! index) $ nodeChildren $ cursorNode cursor

cursorChildren :: Cursor -> [Cursor]
cursorChildren cursor =
  let board = boardResetForChild $ cursorBoard cursor
  in map (\(index, child) -> Cursor { cursorParent' = Just cursor
                                    , cursorChildIndex = index
                                    , cursorNode' = UnmodifiedNode child
                                    , cursorBoard = boardApplyChild board child
                                    })
     $ zip [0..]
     $ nodeChildren
     $ cursorNode cursor

cursorChildCount :: Cursor -> Int
cursorChildCount = length . nodeChildren . cursorNode

cursorChildPlayingAt :: Maybe Coord -> Cursor -> Maybe Cursor
cursorChildPlayingAt move cursor =
  let children = cursorChildren cursor
      color = boardPlayerTurn $ cursorBoard cursor
      hasMove = elem $ moveToProperty color move
  in find (hasMove . nodeProperties . cursorNode) children

-- | This is simply @'nodeProperties' . 'cursorNode'@.
cursorProperties :: Cursor -> [Property]
cursorProperties = nodeProperties . cursorNode

cursorModifyNode :: (Node -> Node) -> Cursor -> Cursor
cursorModifyNode fn cursor =
  let node = fn $ cursorNode cursor
      maybeParent = cursorParent' cursor
  in cursor { cursorNode' =
              -- If we're at a root node, then there is no need to mark the node
              -- as modified, since we'll never move up.
              (if isJust maybeParent then ModifiedNode else UnmodifiedNode) node
            , cursorBoard = case maybeParent of
              Nothing -> rootBoardState node
              Just parent -> boardChild (cursorBoard parent) node
            }

-- | Returns the variations to display for a cursor.  The returned list contains
-- the location and color of 'B' and 'W' properties in variation nodes.
-- Variation nodes are either children of the current node, or siblings of the
-- current node, depending on the variation mode source.
cursorVariations :: VariationModeSource -> Cursor -> [(Coord, Color)]
cursorVariations source cursor =
  case source of
    ShowChildVariations -> collectPlays $ nodeChildren $ cursorNode cursor
    ShowCurrentVariations ->
      case cursorParent cursor of
        Nothing -> []
        Just parent -> collectPlays $ listDeleteAt (cursorChildIndex cursor) $
                       nodeChildren $ cursorNode parent
  where collectPlays :: [Node] -> [(Coord, Color)]
        collectPlays = concatMap collectPlays'
        collectPlays' = concatMap collectPlays'' . nodeProperties
        collectPlays'' prop = case prop of
          B (Just xy) -> [(xy, Black)]
          W (Just xy) -> [(xy, White)]
          _ -> []

moveToProperty :: Color -> Maybe Coord -> Property
moveToProperty color =
  case color of
    Black -> B
    White -> W
