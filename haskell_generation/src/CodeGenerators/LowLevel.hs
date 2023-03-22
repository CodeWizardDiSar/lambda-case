{-# language LambdaCase #-}

module CodeGenerators.LowLevel where

import Data.List
  ( intercalate )
import qualified Data.Map as M
  ( lookup )
import Control.Monad
  ( (>=>) )

import Helpers
  ( Haskell, (==>), (.>) )

import HaskellTypes.LowLevel
  ( Literal(..), ValueName(..), Abstraction(..), ManyAbstractions(..), Input(..) )
import HaskellTypes.Types
  ( TypeName(..) )
import HaskellTypes.AfterParsing
  ( ValType(..), FuncType(..), ValFieldsOrCases(..), FieldAndValType(..) )

import HaskellTypes.Generation
  ( Stateful, value_map_get, value_map_insert, type_map_get )

import CodeGenerators.ErrorMessages
import CodeGenerators.TypeChecking
  ( types_are_equivalent, type_name_to_val_type )

-- All: Literal, ValueName, Abstraction, ManyAbstractions

-- Literal: literal_g, literal_type_inference_g

literal_g = ( \literal val_type -> 
  (val_type == NamedType (TN "Int")) ==> \case
    True -> return $ show literal
    False -> error $ literal_not_int_err val_type
  ) :: Literal -> ValType -> Stateful Haskell

literal_type_inference_g = ( \literal ->
  return (show literal, NamedType $ TN "Int")
  ) :: Literal -> Stateful (Haskell, ValType)

-- ValueName: value_name_g, value_name_type_inference_g

value_name_g = ( \value_name val_type -> 
  value_map_get value_name >>= \map_val_type ->
  types_are_equivalent val_type map_val_type >>= \case
    False -> error $ type_check_err value_name val_type map_val_type
    True -> return $ value_name_to_hs value_name
  ) :: ValueName -> ValType -> Stateful Haskell

value_name_type_inference_g = ( \value_name ->
  value_map_get value_name >>= \map_val_type ->
  return (value_name_to_hs value_name, map_val_type)
  ) :: ValueName -> Stateful (Haskell, ValType)

value_name_to_hs = \case
  VN "true" -> "True"
  VN "false" -> "False"
  value_name -> show value_name
  :: ValueName -> Haskell

-- Abstraction:
-- abstraction_g, val_name_insert_and_return, use_fields_g, field_and_val_type_g

abstraction_g = ( \case
  AbstractionName value_name -> val_name_insert_and_return value_name
  UseFields -> use_fields_g
  ) :: Abstraction -> ValType -> Stateful Haskell

val_name_insert_and_return = ( \value_name val_type ->
  value_map_insert value_name val_type >> return (show value_name)
  ) :: ValueName -> ValType -> Stateful Haskell

use_fields_g = ( \val_type -> case val_type of
  NamedType type_name -> use_fields_type_name_g type_name val_type
  ProdType types -> use_fields_prod_type_g types val_type
  _ -> undefined 
  ) :: ValType -> Stateful Haskell

use_fields_type_name_g = ( \type_name val_type ->
  type_map_get type_name "use_fields_type_name_g" >>= \case
    FieldAndValTypeList fields -> 
      value_map_insert (VN "tuple") val_type >>
      mapM field_and_val_type_g fields >>= \val_names ->
      return $
        "tuple@(" ++ show type_name ++ "C" ++ concatMap (" " ++) val_names ++ ")"
    _ -> undefined
  ) :: TypeName -> ValType -> Stateful Haskell

use_fields_prod_type_g = ( \types val_type ->
  value_map_insert (VN "tuple") val_type >>
  zipWith val_name_insert_and_return prod_type_fields types ==> sequence >>=
    \val_names ->
  return $ "(" ++ intercalate ", " val_names ++ ")"
  ) :: [ ValType ] -> ValType -> Stateful Haskell

prod_type_fields = map VN [ "first", "second", "third", "fourth", "fifth" ]
  :: [ ValueName ]

field_and_val_type_g = ( \(FVT field_name field_type) ->
  val_name_insert_and_return field_name field_type
  ) :: FieldAndValType -> Stateful Haskell

-- ManyAbstractions: many_abstractions_g

many_abstractions_g = ( \(Abstractions abstraction1 abstraction2 abstractions) ->
  abstractions_g (abstraction1 : abstraction2 : abstractions)
  ) :: ManyAbstractions -> ValType -> Stateful (ValType, Haskell)

-- Input: input_g, abstractions_g

input_g = ( \input val_type ->
  let 
  case_result = case input of
    OneAbstraction abstraction -> abstractions_g [ abstraction ] val_type 
    ManyAbstractions many_abs -> many_abstractions_g many_abs val_type
    :: Stateful (ValType, Haskell)
  in
  case_result >>= \(val_t, hs) -> return (val_t, "\\" ++ hs ++ " -> ")
  ) :: Input -> ValType -> Stateful (ValType, Haskell)

abstractions_g = ( \abstractions val_type -> case abstractions of
  [] -> return (val_type, "")
  abs1 : other_abs -> case val_type of
    FuncType (InAndOutType input_type output_type) -> 
      abstraction_g abs1 input_type >>= \abs1_hs ->
      abstractions_g other_abs output_type >>= \(abs_type, other_abs_hs) ->
      return (abs_type, abs1_hs ++ " " ++ other_abs_hs)
    _ -> undefined
  ) :: [ Abstraction ] -> ValType -> Stateful (ValType, Haskell)
