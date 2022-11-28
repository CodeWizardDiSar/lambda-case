{-# language LambdaCase #-}

module CodeGenerators.Types where

import Data.List
  ( intercalate )
import qualified Data.Map as M
  ( insert, lookup )

import Helpers
  ( Haskell, (==>), (.>), parenthesis_comma_sep_g )

import HaskellTypes.LowLevel
  ( ValueName(..) )
import HaskellTypes.Types
  ( TypeName(..), BaseType(..), ValueType(..), FieldAndType(..), TupleType(..)
  , OrType(..), CaseAndType(..) )
import HaskellTypes.Generation
  ( Stateful, tuple_type_map_lookup, tuple_type_map_insert, or_type_map_lookup
  , or_type_map_insert, value_map_insert )

import CodeGenerators.LowLevel
  ( value_name_g )
import CodeGenerators.ErrorMessages
  ( tuple_type_err_msg, or_type_err_msg )

-- All: TypeName, BaseType, ValueType, TupleType

-- TypeName
type_name_g = show
  :: TypeName -> Haskell

-- BaseType
base_type_g = ( \case
  TupleType vts -> parenthesis_comma_sep_g value_type_g vts

  ParenthesisType vt -> case vt of
    (AbsTypesAndResType [] bt) -> base_type_g bt
    _ -> "(" ++ value_type_g vt ++ ")"

  TypeName tn -> type_name_g tn
  ) :: BaseType -> Haskell

-- ValueType
value_type_g = ( \(AbsTypesAndResType bts bt) -> 
  bts==>concatMap (base_type_g .> (++ " -> ")) ++ base_type_g bt
  ) :: ValueType -> Haskell

-- TupleType
tuple_type_g = ( \(NameAndValue tn ttv) -> tuple_type_map_lookup tn >>= \case
  Just _ -> error tuple_type_err_msg

  Nothing ->
    let
    additional_bt = TypeName tn
      :: BaseType

    field_and_type_g = ( \(FT vn vt@(AbsTypesAndResType bts bt) ) ->
      value_map_insert
        (VN $ "get_" ++ value_name_g vn)
        (AbsTypesAndResType (additional_bt : bts) bt) >>
      return ("get_" ++ value_name_g vn ++ " :: " ++ value_type_g vt)
      ) :: FieldAndType -> Stateful Haskell

    tuple_value_g =
      ttv==>mapM field_and_type_g >>= \ttv_g ->
      return $ type_name_g tn ++ "C { " ++ intercalate ", " ttv_g ++ " }"
      :: Stateful Haskell
    in
    tuple_type_map_insert tn ttv >> tuple_value_g >>= \tv_g ->
    return $
      "data " ++ type_name_g tn ++ " =\n  " ++ tv_g ++ "\n  deriving Show\n"
  ) :: TupleType -> Stateful Haskell

-- OrType
or_type_g = ( \(NameAndValues tn otvs) -> or_type_map_lookup tn >>= \case
  Just _ -> error or_type_err_msg

  Nothing ->
    let
    name_bt = TypeName tn
      :: BaseType

    case_and_type_g = ( \(CT vn _ ) ->
      value_map_insert
        (VN $ "is_" ++ value_name_g vn)
        (AbsTypesAndResType [ name_bt ] $ TypeName $ TN "Bool") >>
      return
        ("is_" ++ value_name_g vn ++ " = " ++ "insert function def " ++
         "\n  :: " ++ "insert type -> Bool")
      ) :: CaseAndType -> Stateful Haskell

    or_value_g =
      otvs==>mapM case_and_type_g >>= \otvs_g ->
      return $ type_name_g tn ++ "C " ++ intercalate " |  " otvs_g ++ " }"
      :: Stateful Haskell
    in
    or_type_map_insert tn otvs >> or_value_g >>= \tv_g ->
    return $
      "data " ++ type_name_g tn ++ " =\n  " ++ tv_g ++ "\n  deriving Show\n"
  ) :: OrType -> Stateful Haskell
