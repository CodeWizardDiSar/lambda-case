module GenerationState.InitialState where

import qualified Data.Map as M (empty, fromList)

import ParsingTypes.LowLevel (ValueName(..))
import ParsingTypes.Types (TypeName(..))

import IntermediateTypes.Types
import IntermediateTypes.TypeDefinitions (TypeInfo(..))

import GenerationState.TypesAndOperations (ValueMap, TypeMap, GenerationState(..))

-- Initial state:
-- int, int_x_int, bool, int_to_int_to_int
-- init_value_map, init_state

int = TypeApp $ TypeConsAndInputs' (TN "Int") []
  :: ValType

int_x_int = ProdType [int, int]
  :: ValType

bool = TypeApp $ TypeConsAndInputs' (TN "Bool") []
  :: ValType

int_to_int_to_int =
  [ FuncType $
    InAndOutTs int $ FuncType $ InAndOutTs int int ]
  :: [ ValType ]

init_value_map = 
  M.fromList
    [ (VN "div", int_to_int_to_int)
    , (VN "mod", int_to_int_to_int)
    , (VN "get_1st", [ FuncType $ InAndOutTs int_x_int int ])
    , ( VN "get_all_but_1st"
      , [ FuncType $ InAndOutTs int_x_int int ]
      )
    , (VN "abs", [ FuncType $ InAndOutTs int int ])
    , (VN "max", int_to_int_to_int)
    , (VN "min", int_to_int_to_int)
    , (VN "true", [ bool ])
    , (VN "false", [ bool ])
    ]
  :: ValueMap

init_type_map =
  M.fromList
   [ (TN "Int", IntType) ]
  :: TypeMap

init_state = GS 0 init_value_map init_type_map []
  :: GenerationState
