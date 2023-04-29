module CodeGenerators.OperatorValues where

import Data.List (intercalate)
import Control.Monad (zipWithM, (>=>))
import Control.Monad.Trans.Except (throwE, catchE)

import Helpers (Haskell, Error, (==>), (.>), indent)

import ParsingTypes.LowLevel (ValueName(..))
import ParsingTypes.Types (TypeName(..))
import ParsingTypes.OperatorValues

import IntermediateTypes.Types 
import IntermediateTypes.TypeDefinitions (TTField(..), TypeInfo(..))
import IntermediateTypes.Values

import Conversions.Values

import GenerationState.TypesAndOperations

import GenerationHelpers.ErrorMessages
import GenerationHelpers.TypeChecking (equiv_types)

import CodeGenerators.LowLevel

-- All:
-- Parenthesis, Tuple, MathApplication, BaseValue,
-- FuncAppChain, MultExpr, AddSubExpr,
-- Equality, PureOpExpr, InputOpExpr, OperatorExpression

-- Parenthesis: parenthesis_g, paren_type_inf_g

parenthesis_g = ( \(InnerExpr expr) expr_t ->
  operator_expression_g expr expr_t >>= \expr_hs ->
  return $ "(" ++ expr_hs ++ ")"
  ) :: Parenthesis -> ValType -> Stateful Haskell

paren_type_inf_g = ( \(InnerExpr expr) ->
  op_expr_type_inf_g expr >>= \(expr_hs, expr_t) ->
  return ("(" ++ expr_hs ++ ")", expr_t)
  ) :: Parenthesis -> Stateful (Haskell, ValType)

-- Tuple:
-- tuple_g, tuple_t_name_g, tuple_vals_prod_types_g,
-- tuple_vals_field_types_g, tuple_type_inf_g

tuple_g = ( \(TupleExpressions val1 val2 vals) -> \case
  FuncType _ -> throwE "Tuple can't have function type"
  TypeApp (ConsAndInTs t_name _) -> tuple_t_name_g (val1 : val2 : vals) t_name
  ProdType types -> tuple_vals_prod_types_g (val1 : val2 : vals) types
  _ -> undefined
  ) :: Tuple -> ValType -> Stateful Haskell

tuple_t_name_g = ( \vals t_name -> type_map_get t_name >>= \case
  OrType _ _ -> throwE "Tuple can't be an or_type"
  TupleType _ fields -> tuple_fields_g vals fields t_name
  IntType -> throwE "Tuple can't be an Int"
  CharType -> throwE "Tuple can't be a Char"
  ) :: [ OperatorExpression ] -> TypeName -> Stateful Haskell

tuple_fields_g = ( \vals fields t_name -> case length vals == length fields of 
  False -> throwE tuple_field_length_err
  True -> tuple_vals_field_types_g vals (map get_type fields) t_name
  ) :: [ OperatorExpression ] -> [ TTField ] -> TypeName -> Stateful Haskell

tuple_vals_field_types_g = ( \vals types t_name ->
  get_ind_lev >>= \ind_lev ->
  zipWithM operator_expression_g vals types
    >>= concatMap ( \val_hs -> " (" ++ val_hs ++ ")" ) .> \vals_hs -> 
  return $
    "\n" ++ indent (ind_lev + 1) ++ "(C" ++ show t_name ++ vals_hs ++ ")"
  ) :: [ OperatorExpression ] -> [ ValType ] -> TypeName -> Stateful Haskell

tuple_vals_prod_types_g = ( \vals types -> case length types == length vals of
  False -> throwE "Length of tuple does not match length of product type"
  True -> 
    zipWithM operator_expression_g vals types >>= \vals_hs ->
    return $ "(" ++ intercalate ", " vals_hs ++ ")"
  ) :: [ OperatorExpression ] -> [ ValType ] -> Stateful Haskell

tuple_type_inf_g = ( \(TupleExpressions val1 val2 vals) ->
  mapM op_expr_type_inf_g (val1 : val2 : vals) >>= unzip .> \(vals_hs, ts) ->
  return ("(" ++ intercalate ", " vals_hs ++ ")", ProdType ts)
  ) :: Tuple -> Stateful (Haskell, ValType)

-- MathApplication: math_application_g, math_app_type_inf_g

math_application_g =
  math_app_to_app_tree .> application_tree_g
  :: MathApplication -> ValType -> Stateful Haskell

math_app_type_inf_g =  
  math_app_to_app_tree .> app_tree_type_inf_g
  :: MathApplication -> Stateful (Haskell, ValType)

-- BaseValue: base_value_g, base_value_type_inf_g

base_value_g = ( \case
  Parenthesis parenthesis -> parenthesis_g parenthesis
  Tuple tuple -> tuple_g tuple
  Literal literal -> literal_g literal
  ValueName value_name -> value_name_g value_name
  MathApplication math_application -> math_application_g math_application
  ) :: BaseValue -> ValType -> Stateful Haskell

base_value_type_inf_g = ( \case
  Parenthesis parenthesis -> paren_type_inf_g parenthesis
  Tuple tuple -> tuple_type_inf_g tuple
  Literal literal -> literal_type_inf_g literal
  ValueName value_name -> value_name_type_inf_g value_name
  MathApplication math_application -> math_app_type_inf_g math_application
  ) :: BaseValue -> Stateful (Haskell, ValType)

-- FuncAppChain: func_app_chain_g, func_app_chain_type_inf_g,

func_app_chain_g = 
  func_app_chain_conv .> application_tree_g
  :: FuncAppChain -> ValType -> Stateful Haskell

func_app_chain_type_inf_g = 
  func_app_chain_conv .> app_tree_type_inf_g
  :: FuncAppChain -> Stateful (Haskell, ValType)

-- ApplicationTree: application_tree_g, app_tree_type_inf_g

application_tree_g = ( \case 
  BaseValueLeaf base_value -> base_value_g base_value
  Application application -> application_g application
  ) :: ApplicationTree -> ValType -> Stateful Haskell

app_tree_type_inf_g = ( \case 
  Application application -> application_type_inf_g application
  BaseValueLeaf base_value -> base_value_type_inf_g base_value
  ) :: ApplicationTree -> Stateful (Haskell, ValType)

-- Application: application_g, application_type_inf_g, normal_app_type_inf_g

application_g = ( \application val_type ->
  application_type_inf_g application >>= \(application_hs, application_t) ->
  equiv_types val_type application_t >>= \case 
    True -> return application_hs
    False -> throwE $ type_check_err (show application) val_type application_t
  ) :: Application -> ValType -> Stateful Haskell

application_type_inf_g = ( \application@(AppTrees tree1 tree2) ->
  app_tree_type_inf_g tree1 >>= \(tree1_hs, tree1_t) ->
  case tree1_t of 
    FuncType func_type ->
      catchE
        (normal_app_type_inf_g tree1_hs func_type tree2)
        (application_handler application func_type)
    _ -> throwE $
      "Cannot apply something that is not a function:\n" ++ show tree1 ++ "\n"
  ) :: Application -> Stateful (Haskell, ValType)

normal_app_type_inf_g = (
  \tree1_hs func_type@(InAndOutTs input_t output_t) tree2 -> 
  application_tree_g tree2 input_t >>= \tree2_hs ->
  let 
  tree2_hs' = case tree2 of 
    Application _ -> "(" ++ tree2_hs ++ ")"
    _ -> tree2_hs
    :: Haskell
  in
  return (tree1_hs ++ " " ++ tree2_hs', output_t) 
  ) :: Haskell -> FuncType -> ApplicationTree -> Stateful (Haskell, ValType)

-- Application (handlers): application_handler

application_handler = ( \app@(AppTrees tree1 tree2) (InAndOutTs input_t _) err ->
  case tree2 of 
    BaseValueLeaf (Tuple tuple) -> app_handler_tuple tree1 tuple input_t err
    _ -> general_app_handler app input_t err
  ) :: Application -> FuncType -> Error -> Stateful (Haskell, ValType)

-- app_handler_tuple, app_handler_tuple_correct

app_handler_tuple = ( \tree1 tuple@(TupleExpressions val1 _ _) input_t err -> 
  op_expr_type_inf_g val1 >>= \case
    (_, op_expr_t) -> equiv_types input_t op_expr_t >>= \case 
      True -> app_handler_tuple_correct tree1 tuple
      _ -> throwE err
  ) :: ApplicationTree -> Tuple -> ValType -> Error -> Stateful (Haskell, ValType)

app_handler_tuple_correct = ( \tree1 (TupleExpressions val1 val2 vals) -> 
  let
  tree1' = 
    Application $ AppTrees tree1 $ BaseValueLeaf $ Parenthesis $ InnerExpr val1
  tree2' = BaseValueLeaf $ case vals of 
    [] -> Parenthesis $ InnerExpr val2
    val3 : other_vals -> Tuple $ TupleExpressions val2 val3 other_vals
  in
  application_type_inf_g $ AppTrees tree1' tree2'
  ) :: ApplicationTree -> Tuple -> Stateful (Haskell, ValType)

-- general_app_handler, general_app_handler_correct

general_app_handler = ( \app@(AppTrees tree1 tree2) input_t err ->
  app_tree_type_inf_g tree2 >>= \case
    (_,ProdType (t1:_)) -> equiv_types input_t t1 >>= \case 
      True -> general_app_handler_correct app
      _ -> throwE err
    _ -> throwE err
  ) :: Application -> ValType -> Error -> Stateful (Haskell, ValType)

general_app_handler_correct = ( \(AppTrees tree1 tree2) ->
  let
  tree2_1st = Application $ AppTrees get_1st_tree tree2
    :: ApplicationTree
  tree1' = Application $ AppTrees tree1 tree2_1st
    :: ApplicationTree

  tree2_rest = Application $ AppTrees get_all_but_1st_tree tree2
    :: ApplicationTree
  in
  application_type_inf_g $ AppTrees tree1' tree2_rest
  ) :: Application -> Stateful (Haskell, ValType)

-- general_app_handler (helpers): get_1st_tree, get_all_but_1st_tree

get_1st_tree = BaseValueLeaf $ ValueName $ VN "get_1st"
  :: ApplicationTree

get_all_but_1st_tree = BaseValueLeaf $ ValueName $ VN "get_all_but_1st"
  :: ApplicationTree

-- MultExpr: mult_expr_g

mult_expr_g = ( \(Factors mul_f1 mul_fs) val_type -> 
  mapM (flip func_app_chain_g val_type) (mul_f1 : mul_fs) >>=
  intercalate " * " .> return
  ) :: MultExpr -> ValType -> Stateful Haskell

mult_expr_type_inf_g = ( \(Factors mul_f1 mul_fs) ->
  func_app_chain_type_inf_g mul_f1 >>= \(hs1, t1) ->
  case mul_fs of
    [] -> return (hs1, t1)
    _ ->
      mapM (flip func_app_chain_g t1) mul_fs >>= \mul_fs_hs ->
      return (intercalate " * " mul_fs_hs, t1)
  ) :: MultExpr -> Stateful (Haskell, ValType)

-- AddSubExpr:
-- add_sub_expr_g, add_sub_expr_type_inf_g, add_sub_or_term_g,
-- add_sub_expr_type_inf_g, addition_g, subtraction_g, add_sub_g

add_sub_expr_g = add_sub_expr_conv .> add_sub_or_mexpr_g
  :: AddSubExpr -> ValType -> Stateful Haskell

add_sub_expr_type_inf_g = add_sub_expr_conv .> add_sub_or_term_type_inf_g 
  :: AddSubExpr -> Stateful (Haskell, ValType)

add_sub_or_mexpr_g = ( \case
  Addition addition -> addition_g addition
  Subtraction subtraction -> subtraction_g subtraction
  MultExpr mult_expr -> mult_expr_g mult_expr
  ) :: AddSubOrMExpr -> ValType -> Stateful Haskell

add_sub_or_term_type_inf_g = ( \case
  Addition addition -> addition_g addition int >>= \hs -> return (hs, int)
  Subtraction subtr -> subtraction_g subtr int >>= \hs -> return (hs, int)
  MultExpr mult_expr -> mult_expr_type_inf_g mult_expr
  ) :: AddSubOrMExpr -> Stateful (Haskell, ValType)

addition_g = ( \(ExprPlusMExpr expr mult_expr) ->
  add_sub_g expr " + " mult_expr
  ) :: Addition -> ValType -> Stateful Haskell

subtraction_g = ( \(ExprMinusMExpr expr mult_expr) ->
  add_sub_g expr " - " mult_expr
  ) :: Subtraction -> ValType -> Stateful Haskell

add_sub_g = ( \expr op mult_expr val_type ->
  add_sub_or_mexpr_g expr val_type >>= \expr_hs ->
  mult_expr_g mult_expr val_type >>= \term_hs ->
  return $ expr_hs ++ op ++ term_hs
  ) :: AddSubOrMExpr -> String -> MultExpr -> ValType -> Stateful Haskell

-- Equality: equality_g

equality_g = ( \(EqualityTerms term1 term2) -> \case 
  TypeApp (ConsAndInTs (TN "Bool") []) ->
    add_sub_expr_g term1 int >>= \term1_hs ->
    add_sub_expr_g  term2 int >>= \term2_hs ->
    return $ term1_hs ++ " == " ++ term2_hs
  t -> throwE $ "Equality must be of type Bool, not: " ++ show t
  ) :: Equality -> ValType -> Stateful Haskell

equality_type_inf_g = ( \(EqualityTerms term1 term2) ->
  add_sub_expr_g term1 int >>= \term1_hs ->
  add_sub_expr_g term2 int >>= \term2_hs ->
  return (term1_hs ++ " == " ++ term2_hs, bool)
  ) :: Equality -> Stateful (Haskell, ValType)

-- PureOpExpr: pure_operator_expression_g, pure_op_expr_type_inf_g

pure_operator_expression_g = ( \case
  AddSubExpr add_sub_expr -> add_sub_expr_g add_sub_expr
  Equality equality -> equality_g equality
  ) :: PureOpExpr -> ValType -> Stateful Haskell

pure_op_expr_type_inf_g = ( \case
  AddSubExpr add_sub_expr -> add_sub_expr_type_inf_g add_sub_expr
  Equality equality -> equality_type_inf_g equality
  ) :: PureOpExpr -> Stateful (Haskell, ValType)

-- InputOpExpr: input_operator_expression_g, input_op_expr_type_inf_g

input_operator_expression_g = ( \(InputAndPureOpExpr input op_expr) ->
  input_g input >=> \(out_t, input_hs) ->
  pure_operator_expression_g op_expr out_t >>= \op_expr_hs ->
  input_val_map_remove input >>
  return (input_hs ++ op_expr_hs)
  ) :: InputOpExpr -> ValType -> Stateful Haskell

input_op_expr_type_inf_g = ( \(InputAndPureOpExpr as opval) ->
  undefined
  ) :: InputOpExpr -> Stateful (Haskell, ValType)

-- OperatorExpression: operator_expression_g, input_op_expr_type_inf_g

operator_expression_g = ( \case
  InputOpExpr input_op_expr -> input_operator_expression_g input_op_expr
  PureOpExpr op_expr -> pure_operator_expression_g op_expr
  ) :: OperatorExpression -> ValType -> Stateful Haskell

op_expr_type_inf_g = ( \case
  InputOpExpr input_op_expr -> input_op_expr_type_inf_g input_op_expr
  PureOpExpr op_expr -> pure_op_expr_type_inf_g op_expr
  ) :: OperatorExpression -> Stateful (Haskell, ValType)

