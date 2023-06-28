module Intermediate.Types.Values where

import Helpers
import Parsing.Types.LowLevel
import Parsing.Types.OperatorValues 

-- Application, ApplicationTree

data Application =
  AppTrees ApplicationTree ApplicationTree

instance Show Application where
  show = \(AppTrees tree1 tree2) -> show tree2 ++ "==>" ++ show tree1

-- 
data ApplicationTree = 
  Application Application | BaseVal2Leaf BaseVal2

instance Show ApplicationTree where
  show = \case 
    Application app -> show app
    BaseVal2Leaf base_val -> show base_val

-- BaseVal2

data BaseVal2 =
  Literal2 (Pos Literal) | ValueName2 (Pos ValueName) | ParenExpr2 (Pos ParenExpr)

instance Show BaseVal2 where
  show = \case
    Literal2 lit -> show lit
    ValueName2 val_name -> show val_name
    ParenExpr2 paren_expr -> show paren_expr

-- Addition, Subtraction, AddSubOrMExpr

data Addition = 
  ExprPlusMExpr AddSubOrMExpr (Pos MultExpr)

data Subtraction = 
  ExprMinusMExpr AddSubOrMExpr (Pos MultExpr)

data AddSubOrMExpr =
  Addition Addition | Subtraction Subtraction | MultExpr (Pos MultExpr)

-- Input2

data Input2 =
  Input2 [ Pos Abstraction ]