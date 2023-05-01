module CodeGenerators.LowLevel where

import Data.List (intercalate)
import Control.Monad ((>=>), zipWithM)
import Control.Monad.Trans.Except (throwE)

import Helpers (Haskell, (==>), (.>))

import ParsingTypes.LowLevel
import ParsingTypes.Types (TypeName(..))

import IntermediateTypes.Types
import IntermediateTypes.TypeDefinitions (TTField(..), TypeInfo(..))

import GenerationState.TypesAndOperations

import GenerationHelpers.ErrorMessages
import GenerationHelpers.TypeChecking (equiv_types)
import GenerationHelpers.Helpers 

-- All: Literal, ValueName, Abstraction, ManyAbstractions, Input

-- Literal: literal_g, literal_type_inf_g

literal_g = ( \lit val_type -> (val_type == int) ==> \case
  True -> return $ show lit
  False -> throwE $ lit_not_int_err val_type
  ) :: Literal -> ValType -> Stateful Haskell

literal_type_inf_g = ( \lit -> return (show lit, int) )
  :: Literal -> Stateful (Haskell, ValType)

-- ValueName: value_name_g, value_name_type_inf_g, check_vn_in_or_t_cs_g

value_name_g = ( \val_name val_type -> 
  value_map_get val_name >>= \map_val_type ->
  equiv_types val_type map_val_type >>= \case
    False -> throwE $ type_check_err (show val_name) val_type map_val_type
    True -> check_vn_in_or_t_cs_g val_name
  ) :: ValueName -> ValType -> Stateful Haskell

value_name_type_inf_g = ( \val_name -> 
  value_map_get val_name >>= \map_val_type ->
  check_vn_in_or_t_cs_g val_name >>= \value_name_hs ->
  return (value_name_hs, map_val_type)
  ) :: ValueName -> Stateful (Haskell, ValType)

check_vn_in_or_t_cs_g = ( \val_name -> in_or_t_cs val_name >>= \case
  True -> return $ "C" ++ show val_name
  _ -> return $ show val_name
  ) :: ValueName -> Stateful Haskell

-- Abstraction: abstraction_g, abs_val_map_remove, helpers

abstraction_g = ( \case
  AbstractionName val_name -> val_n_ins_and_ret_hs val_name
  UseFields -> use_fields_g
  ) :: Abstraction -> ValType -> Stateful Haskell

abs_val_map_remove = ( \case
  AbstractionName val_name -> value_map_remove val_name
  UseFields -> use_fs_map_remove
  ) :: Abstraction -> Stateful ()

-- Abstraction (abstraction_g):
-- use_fields_g, use_fields_tuple_matching_g, use_fields_type_name_g,
-- prod_type_matching_g

use_fields_g = ( \val_type ->
  value_map_insert (VN "tuple") val_type >>
  use_fields_tuple_matching_g val_type >>= \tuple_matching_hs ->
  return $ "tuple" ++ tuple_matching_hs
  ) :: ValType -> Stateful Haskell

use_fields_tuple_matching_g = ( \case
  TypeApp (ConsAndTIns type_name _) -> use_fields_type_name_g type_name
  ProdType types -> prod_type_matching_g types
  val_t -> throwE $ use_fields_err val_t
  ) :: ValType -> Stateful Haskell

use_fields_type_name_g = ( \type_name ->
  type_name_matching_g (throwE $ use_fields_err $ tn_to_val_t type_name) type_name
  ) :: TypeName -> Stateful Haskell

-- Abstraction (abs_val_map_remove): use_fs_map_remove, use_fs_tn_map_remove

use_fs_map_remove = ( 
  value_map_get (VN "tuple") >>= \tuple_t -> 
  value_map_remove (VN "tuple") >> case tuple_t of
    TypeApp (ConsAndTIns type_name _) -> use_fs_tn_map_remove type_name 
    ProdType types -> mapM_ value_map_remove $ take (length types) prod_t_field_ns
    _ -> error "use_fs_map_remove: should be impossible"
  ) :: Stateful ()

use_fs_tn_map_remove = ( type_map_get >=> \case
  TupleType _ fields -> mapM_ (get_name .> value_map_remove) fields 
  _ -> error "use_fs_tn_map_remove: should be impossible"
  ) :: TypeName -> Stateful ()

-- Abstraction (helpers):
-- val_n_ins_and_ret_hs, field_ins_and_ret_hs, prod_t_field_ns

-- ManyAbstractions: many_abstractions_g, many_abs_val_map_remove

many_abstractions_g = ( \(Abstractions abs1 abs2 abstractions) ->
  abstractions_g (abs1 : abs2 : abstractions)
  ) :: ManyAbstractions -> ValType -> Stateful (ValType, Haskell)

many_abs_val_map_remove = ( \(Abstractions abs1 abs2 abstractions) ->
  mapM_ abs_val_map_remove $ abs1 : abs2 : abstractions
  ) :: ManyAbstractions -> Stateful ()

-- Input: input_g, input_abstractions_g, input_val_map_remove

input_g = ( \input val_type ->
  input_abstractions_g input val_type >>= \(final_t, input_hs) ->
  return (final_t, "\\" ++ input_hs ++ "-> ")
  ) :: Input -> ValType -> Stateful (ValType, Haskell)

input_abstractions_g = ( \case
  OneAbstraction abstraction -> abstractions_g [ abstraction ]
  ManyAbstractions many_abs -> many_abstractions_g many_abs
  ) :: Input -> ValType ->  Stateful (ValType, Haskell)

input_val_map_remove = ( \case
  OneAbstraction abs -> abs_val_map_remove abs
  ManyAbstractions many_abs -> many_abs_val_map_remove many_abs
  ) :: Input -> Stateful ()

-- abstractions_g

abstractions_g = ( \case
  [] -> \val_type -> return (val_type, "")
  abs1 : other_abs -> abstractions_check_func_t_g abs1 other_abs
  ) :: [ Abstraction ] -> ValType -> Stateful (ValType, Haskell)

abstractions_check_func_t_g = ( \abs1 other_abs -> \case
  FuncType func_t -> abstractions_func_t_g abs1 other_abs func_t
  val_type -> throwE $ not_func_t_err abs1 val_type
  ) :: Abstraction -> [ Abstraction ] -> ValType -> Stateful (ValType, Haskell)

abstractions_func_t_g = ( \abs1 other_abs (InAndOutTs in_t out_t) -> 
  abstraction_g abs1 in_t >>= \abs1_hs ->
  abstractions_g other_abs out_t >>= \(final_t, other_abs_hs) ->
  return (final_t, abs1_hs ++ " " ++ other_abs_hs)
  ) :: Abstraction -> [ Abstraction ] -> FuncType -> Stateful (ValType, Haskell)
