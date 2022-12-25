{-# language LambdaCase #-}

module CodeGenerators.Values where

import Data.List
  ( intercalate, splitAt )
import Control.Monad
  ( foldM )
import Control.Monad.State
  ( (>=>) )

import Helpers
  ( Haskell, (==>), (.>), indent )

import HaskellTypes.LowLevel
  ( LiteralOrValueName(..), ValueName(..), Abstraction(..) )
import HaskellTypes.Types
  ( TypeName(..), ParenType(..), BaseType(..), ValueType(..), FieldAndType(..)
  , FieldsOrCases(..), bt_to_vt, vt_to_bt )
import HaskellTypes.Values
import HaskellTypes.AfterParsing
  ( ApplicationTree(..), to_application_tree, to_application_tree )
import HaskellTypes.Generation
  ( Stateful, get_indent_level, update_indent_level, type_map_get, value_map_get
  , value_map_insert )

import CodeGenerators.ErrorMessages
import CodeGenerators.LowLevel
  ( literal_g, literal_type_inference_g, literal_or_value_name_g
  , literal_or_value_name_type_inference_g, abstractions_g, vts_are_equivalent )
import CodeGenerators.Types
  ( value_type_g )


-- All:
-- ParenthesisValue, BaseValue, OneArgApplications,
-- multiplication_factor_g, multiplication_g, subtraction_factor_g, subtraction_g,
-- equality_factor_g, equality_g
-- operator_value_g, many_args_arg_value_g, ManyArgsApplication,
-- UseFields, SpecificCase, Cases,
-- name_type_and_value_g, name_type_and_value_lists_g,
-- ntav_or_ntav_lists_g, names_types_and_values_g, Where,
-- OutputValue, LambdaValue

-- ParenthesisValue:
-- parenthesis_value_g, value_type_tuple_values_g, base_type_tuple_values_g, 
-- value_types_tuple_values_g, type_name_tuple_values_g,
-- correct_type_name_tuple_values_g   
parenthesis_value_g = ( \vt -> \case
  Parenthesis v -> value_g vt v >>= \v_g -> return $ "(" ++ v_g ++ ")"
  Tuple vs -> value_type_tuple_values_g vt vs
  ) :: ValueType -> ParenthesisValue -> Stateful Haskell

value_type_tuple_values_g = ( \case
  vt@(AbsTypesAndResType (_:_) _) -> \vs -> error $ tuple_fun_type_err vs vt
  AbsTypesAndResType [] bt -> base_type_tuple_values_g bt
  ) :: ValueType -> [ LambdaValue ] -> Stateful Haskell

base_type_tuple_values_g = ( \case
  ParenType pt -> paren_type_tuple_values_g pt
  TypeName tn -> type_name_tuple_values_g tn
  ) :: BaseType -> [ LambdaValue ] -> Stateful Haskell

paren_type_tuple_values_g = ( \case
  TupleType vt1 vt2 vts -> value_types_tuple_values_g $ vt1 : vt2 : vts
  ParenVT vt -> value_type_tuple_values_g vt
  ) :: ParenType -> [ LambdaValue ] -> Stateful Haskell

value_types_tuple_values_g = ( \vts vs -> case length vts == length vs of
  False -> error tuple_values_types_lengths_dont_match_err
  True -> 
    zipWith value_g vts vs==>sequence >>= \vs_g ->
    return $ "( " ++ intercalate ", " vs_g ++ " )"
  ) :: [ ValueType ] -> [ LambdaValue ] -> Stateful Haskell

type_name_tuple_values_g = ( \tn vs -> type_map_get tn >>= \case
  FieldAndTypeList fatl -> case length vs == length fatl of 
    False -> error values_fields_lengths_dont_match_err
    True -> correct_type_name_tuple_values_g tn (map get_ft fatl) vs
  CaseAndMaybeTypeList camtl -> undefined camtl
  ) :: TypeName -> [ LambdaValue ] -> Stateful Haskell

correct_type_name_tuple_values_g = ( \tn vts vs ->
  get_indent_level >>= \il ->
  zipWith value_g vts vs==>sequence >>= \vs_g -> 
  return $
  show tn ++ "C" ++
  concatMap (\v_g -> "\n" ++ indent (il + 1) ++ "(" ++ v_g ++ ")") vs_g
  ) :: TypeName -> [ ValueType ] -> [ LambdaValue ] -> Stateful Haskell

parenthesis_value_type_inference_g = ( \case
  Parenthesis v ->
    value_type_inference_g v >>= \( vt, hs ) -> return ( vt, "(" ++ hs ++ ")" )
  Tuple vs ->
    tuple_values_type_inference_g vs
  ) :: ParenthesisValue -> Stateful ( ValueType, Haskell )

tuple_values_type_inference_g = ( \vs ->
  mapM value_type_inference_g vs >>= unzip .> \( vts, vs_g ) -> case vts of
    vt1 : vt2 : vts ->
      return
      ( AbsTypesAndResType [] $ ParenType $ TupleType vt1 vt2 vts
      , "( " ++ intercalate ", " vs_g ++ " )" )
    _ -> undefined
  ) :: [ LambdaValue ] -> Stateful ( ValueType, Haskell )

-- BaseValue: base_value_g, base_value_type_inference_g
base_value_g = ( \vt -> \case
  ParenthesisValue pv -> parenthesis_value_g vt pv
  LiteralOrValueName lovn -> literal_or_value_name_g vt lovn
  ) :: ValueType -> BaseValue -> Stateful Haskell

base_value_type_inference_g = ( \case
  ParenthesisValue pv -> parenthesis_value_type_inference_g pv
  LiteralOrValueName lovn -> literal_or_value_name_type_inference_g lovn
  ) :: BaseValue -> Stateful ( ValueType, Haskell )

-- OneArgApplications:
-- one_arg_applications_g, next_application_g, one_arg_application_g
one_arg_applications_g = ( \vt ->
  to_application_tree .> application_tree_g vt
  ) :: ValueType -> OneArgApplications -> Stateful Haskell

application_tree_g = ( \vt@(AbsTypesAndResType abs_ts res_t) -> \case 
  BaseValueLeaf bv -> base_value_g vt bv
  at ->
    application_tree_type_inference_g at >>= \( at_vt, at_hs ) ->
    vts_are_equivalent vt at_vt >>= \case 
      True -> return at_hs
      False -> error $ "\n" ++ show vt ++ "\n" ++ show at_vt ++ "\n" ++ show at
  ) :: ValueType -> ApplicationTree -> Stateful Haskell

application_tree_type_inference_g = ( \case 
  Application at1 at2 -> application_tree_type_inference_g at1 >>=
    \( vt1@(AbsTypesAndResType abs_ts res_t), hs1 ) -> case abs_ts of 
      [] ->
        error $ "\n" ++ show at1 ++ "\n" ++ show at2 ++ "\n" ++ show vt1 ++ "\n"
      abs_t:rest -> 
        application_tree_g (bt_to_vt abs_t) at2 >>= \hs2 ->
        let 
        hs2_ = case at2 of 
          Application _ _ -> "(" ++ hs2 ++ ")"
          _ -> hs2
        in
        return ( AbsTypesAndResType rest res_t, hs1 ++ " " ++ hs2_ ) 
  BaseValueLeaf bv -> base_value_type_inference_g bv
  ) :: ApplicationTree -> Stateful ( ValueType, Haskell )
-- OneArgApplications end

multiplication_factor_g = ( \vt -> \case
  OneArgAppMF oaas -> one_arg_applications_g vt oaas
  BaseValueMF bv -> base_value_g vt bv
  ) :: ValueType -> MultiplicationFactor -> Stateful Haskell

multiplication_g = ( \vt (Mul mfs) -> 
  mapM (multiplication_factor_g vt) mfs >>= intercalate " * " .> return
  ) :: ValueType -> Multiplication -> Stateful Haskell

subtraction_factor_g = ( \vt -> \case
  MulSF m -> multiplication_g vt m
  MFSF f -> multiplication_factor_g vt f
  ) :: ValueType -> SubtractionFactor -> Stateful Haskell

subtraction_g = ( \vt (Sub sf1 sf2) ->
  subtraction_factor_g vt sf1 >>= \sf1_g ->
  subtraction_factor_g vt sf2 >>= \sf2_g ->
  return $ sf1_g ++ " - " ++ sf2_g
  ) :: ValueType -> Subtraction -> Stateful Haskell

equality_factor_g = ( \vt -> \case
  SubEF s -> subtraction_g vt s
  SFEF f -> subtraction_factor_g vt f
  ) :: ValueType -> EqualityFactor -> Stateful Haskell

equality_g = ( \case 
  (AbsTypesAndResType [] (TypeName (TN "Bool"))) -> \(Equ ef1 ef2) ->
    let int_vt = (AbsTypesAndResType [] (TypeName (TN "Int"))) in
    equality_factor_g int_vt ef1 >>= \ef1_g ->
    equality_factor_g int_vt ef2 >>= \ef2_g ->
    return $ ef1_g ++ " == " ++ ef2_g
  _ -> undefined
  ) :: ValueType -> Equality -> Stateful Haskell

-- OperatorValue: operator_value_g, operator_value_type_inference_g
operator_value_g = ( \vt -> \case
  Equality equ -> equality_g vt equ
  EquF f -> equality_factor_g vt f
  ) :: ValueType -> OperatorValue -> Stateful Haskell

operator_value_type_inference_g = ( \case
  Equality equ -> equality_g vt equ >>= \hs -> return ( vt, hs ) where
    vt = (AbsTypesAndResType [] (TypeName (TN "Bool")))
      :: ValueType

  EquF f -> equality_factor_g vt f >>= \hs -> return ( vt, hs ) where
    vt = (AbsTypesAndResType [] (TypeName (TN "Int")))
      :: ValueType
  ) :: OperatorValue -> Stateful ( ValueType, Haskell )
-- OperatorValue end

many_args_arg_value_g = ( \(AbsTypesAndResType bts bt) (OLV as opval) ->
  case length as > length bts of 
  True -> error $ too_many_abstractions_err as bts
  False -> 
    abstractions_g bts1 as >>= \as_g ->
    operator_value_g (AbsTypesAndResType bts2 bt) opval >>= \nav1_g ->
    return $ as_g ++ nav1_g
    where
    ( bts1, bts2 ) = splitAt (length as) bts
      :: ( [ BaseType ], [ BaseType ] )
  ) :: ValueType -> OperatorLambdaValue -> Stateful Haskell

-- ManyArgsApplication: many_args_application_g, bts_maavs_vn_g, bt_maav_g
many_args_application_g = ( \vt (MAA maavs vn) -> value_map_get vn >>=
  \(AbsTypesAndResType abs_bts res_bt) ->
  let
  ( bts1, bts2 ) = splitAt (length maavs) abs_bts
    :: ( [ BaseType ], [ BaseType ] )
  in
  vts_are_equivalent vt (AbsTypesAndResType bts2 res_bt) >>= \case
    False -> error $
      many_args_types_dont_match_err vt (AbsTypesAndResType bts2 res_bt)
    True -> bts_maavs_vn_g bts1 maavs vn
  ) :: ValueType -> ManyArgsApplication -> Stateful Haskell

bts_maavs_vn_g = ( \bts maavs vn ->
  zipWith bt_maav_g bts maavs==>sequence >>= \maavs_g ->
  return $ show vn ++ concatMap (" " ++) maavs_g
  ) :: [ BaseType ] -> [ OperatorLambdaValue ] -> ValueName -> Stateful Haskell

bt_maav_g = ( \bt maav ->
  let
  maav_vt = case bt of
    ParenType(ParenVT vt) -> vt
    _ -> (AbsTypesAndResType [] bt)
    :: ValueType
  in
  many_args_arg_value_g maav_vt maav >>= \maav_g -> return $ "(" ++ maav_g ++ ")"
  ) :: BaseType -> OperatorLambdaValue -> Stateful Haskell

-- UseFields: use_fields_g, correct_use_fields_g, insert_to_value_map_ret_vn
use_fields_g = ( \vt@(AbsTypesAndResType bts bt) (UF v) -> case bts of 
  [] -> error $ use_fields_not_fun_err vt
  b:bs -> case b of
    ParenType _ -> error $ must_be_tuple_type_err b -- maybe something here?
    TypeName tn -> type_map_get tn >>= \case
      FieldAndTypeList fatl ->
        correct_use_fields_g tn fatl (AbsTypesAndResType bs bt) v
      CaseAndMaybeTypeList catl -> undefined
  ) :: ValueType -> UseFields -> Stateful Haskell

correct_use_fields_g = ( \tn fatl vt v ->
  get_indent_level >>= \il ->
  mapM insert_to_value_map_ret_vn fatl >>= \vns ->
  value_g vt v >>= \v_g ->
  return $
  "\\value@(" ++ show tn ++ "C" ++ concatMap ( show .> (" " ++) ) vns ++ ") -> "
  ++ v_g
  ) :: TypeName -> [ FieldAndType ] -> ValueType -> LambdaValue -> Stateful Haskell

insert_to_value_map_ret_vn = ( \(FT vn vt) -> value_map_insert vn vt >> return vn )
  :: FieldAndType -> Stateful ValueName

-- SpecificCase: specific_case_g, specific_case_type_inference_g
specific_case_g = ( \vt@(AbsTypesAndResType bts bt) sc@(SC lovn v) -> case bts of 
  [] -> error $ specific_case_not_abstraction_err vt sc
  b:bs -> case lovn of 
    Literal l -> literal_g bt_vt l >>= add_value_g 
    ValueName vn -> value_map_insert vn bt_vt >> add_value_g (show vn)
    where
    bt_vt = bt_to_vt b
      :: ValueType
    add_value_g = ( \g ->
      value_g (AbsTypesAndResType bs bt) v >>= \v_g ->
      get_indent_level >>= \i ->
      return $ indent i ++ abs_g g ++ " -> " ++ v_g
      ) :: Haskell -> Stateful Haskell
    abs_g = \case 
      "true" -> "True"
      "false" -> "False"
      g -> g
      :: Haskell -> Haskell
  ) :: ValueType -> SpecificCase -> Stateful Haskell

specific_case_type_inference_g = ( \sc@(SC lovn v) ->
  literal_or_value_name_type_inference_g lovn >>= \( lovn_vt, lovn_g ) ->
  value_type_inference_g v >>= \( AbsTypesAndResType abs res, v_g ) ->
  get_indent_level >>= \i ->
  let
  lovn_bt = case lovn_vt of 
    AbsTypesAndResType [] bt -> bt
    _ -> ParenType $ ParenVT $ lovn_vt
  in
  return
  ( AbsTypesAndResType (lovn_bt : abs) res
  , indent i ++ lovn_g ++ " -> " ++ v_g )
  ) :: SpecificCase -> Stateful ( ValueType, Haskell )

-- Cases: cases_g, 
cases_g = ( \vt (Cs cs) ->
  get_indent_level >>= \i ->
  update_indent_level (i + 1) >> mapM (specific_case_g vt) cs >>= \cs_g ->
  update_indent_level i >> return ("\\case\n" ++ intercalate "\n" cs_g)
  ) :: ValueType -> Cases -> Stateful Haskell

cases_type_inference_g = ( \(Cs cs) -> case cs of
  [] -> undefined
  sc:scs ->
    get_indent_level >>= \i -> update_indent_level (i + 1) >>
    specific_case_type_inference_g sc >>= \( vt, sc_g ) ->
    mapM (specific_case_g vt) scs >>= \scs_g ->
    update_indent_level i >>
    return ( vt, "\\case\n" ++ sc_g ++ "\n" ++ intercalate "\n" scs_g)
  ) :: Cases -> Stateful ( ValueType, Haskell )
-- Cases end

name_type_and_value_g = ( \(NTAV vn vt v) -> 
  value_map_insert vn vt >> value_g vt v >>= \v_g ->
  get_indent_level >>= \i ->
  return $
  "\n" ++ indent i  ++ show vn ++ " :: " ++ value_type_g vt ++ "\n" ++
  indent i  ++ show vn ++ " = " ++ v_g ++ "\n"
  ) :: NameTypeAndValue -> Stateful Haskell

name_type_and_value_lists_g = ( \ntavls@(NTAVLists vns vts vs) -> 
  let
  zip3 = ( \case
    ( vn : vns, vt : vts, v : vs ) -> NTAV vn vt v : zip3 ( vns, vts, vs )
    ( [], [], [] ) -> []
    _ -> error $ name_type_and_value_lists_err ntavls
    ) :: ( [ ValueName ], [ ValueType ], [ LambdaValue ] ) -> [ NameTypeAndValue ]
  in
  zip3 ( vns, vts, vs )==>mapM name_type_and_value_g >>= concat .> return
  ) :: NameTypeAndValueLists -> Stateful Haskell

ntav_or_ntav_lists_g = ( \case 
  NameTypeAndValue ntav -> name_type_and_value_g ntav
  NameTypeAndValueLists ntav_lists -> name_type_and_value_lists_g ntav_lists
  ) :: NTAVOrNTAVLists -> Stateful Haskell

names_types_and_values_g = ( \(NTAVs ntavs) ->
  ntavs==>mapM ntav_or_ntav_lists_g >>= concat .> return
  ) :: NamesTypesAndValues -> Stateful Haskell

-- Where: where_g, where_type_inference_g 
where_g = ( \vt (Where_ v ntavs) ->
  get_indent_level >>= \i -> update_indent_level (i + 1) >>
  names_types_and_values_g ntavs >>= \ntavs_g ->
  value_g vt v >>= \v_g ->
  update_indent_level i >>
  return (
  "\n" ++ indent (i + 1) ++ "let" ++
  "\n" ++ indent (i + 1) ++ ntavs_g ++
  "\n" ++ indent (i + 1) ++ "in" ++
  "\n" ++ indent (i + 1) ++ v_g
  )
  ) :: ValueType -> Where -> Stateful Haskell

where_type_inference_g = ( \(Where_ v ntavs) ->
  get_indent_level >>= \i -> update_indent_level (i + 1) >>
  names_types_and_values_g ntavs >>= \ntavs_g ->
  value_type_inference_g v >>= \( vt, v_g ) ->
  update_indent_level i >>
  return ( vt, "\n" ++ indent (i + 1) ++ v_g ++ " where" ++ ntavs_g )
  ) :: Where -> Stateful ( ValueType, Haskell )

-- OutputValue: output_value_g, output_value_type_inference_g
output_value_g = ( \vt -> \case
  ManyArgsApplication maa -> many_args_application_g vt maa
  UseFields uf -> use_fields_g vt uf
  OperatorValue opval -> operator_value_g vt opval
  Cases cs -> cases_g vt cs
  Where w -> where_g vt w
  ) :: ValueType -> OutputValue -> Stateful Haskell

output_value_type_inference_g = ( \case
  ManyArgsApplication maa -> undefined

  -- cannot infer unless we try to lookup potential fields in the output value 
  -- and infer backwards
  UseFields uf -> undefined

  OperatorValue opval -> operator_value_type_inference_g opval

  -- could infer by looking up cases that are not "..." (need new map?)
  Cases cs -> cases_type_inference_g cs
  Where w -> where_type_inference_g w 
  ) :: OutputValue -> Stateful ( ValueType, Haskell )

-- LambdaValue: value_g, value_type_inference_g
value_g = ( \(AbsTypesAndResType bts bt) (LV as nav) ->
  let
  ( bts1, bts2 ) = splitAt (length as) bts
    :: ( [ BaseType ], [ BaseType ] )
  in
  abstractions_g bts1 as >>= \as_g ->
  output_value_g ( AbsTypesAndResType bts2 bt ) nav >>= \nav_g ->
  return $ as_g ++ nav_g
  ) :: ValueType -> LambdaValue -> Stateful Haskell

value_type_inference_g = ( \case
  (LV [] nav) -> output_value_type_inference_g nav
  _ -> undefined
  ) :: LambdaValue -> Stateful ( ValueType, Haskell )

