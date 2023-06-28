module Parsing.Parsers.Values where

import Text.Parsec
import Text.Parsec.String (Parser)

import Parsing.Types.Types (ValueType)
import Parsing.Types.Values

import Parsing.Parsers.Helpers 
import Parsing.Parsers.LowLevel (literal_p, value_name_p, input_p)
import Parsing.Parsers.Types (value_type_p)
import Parsing.Parsers.OperatorValues (operator_expression_p)

-- All:
-- LitOrValName, Case, DefaultCase, CasesExpr
-- ValueNameTypeAndExpression, Values,
-- ValueOrValues, ValueOrValuesList
-- Where, CasesOrWhere, InputCasesOrWhere, ValueExpression

-- LitOrValName: lit_or_val_name_p

lit_or_val_name_p =
  Literal <$> literal_p <|> ValueName <$> value_name_p
  :: Parser LitOrValName

-- Case: specific_case_p

specific_case_p =
  spicy_new_line >> lit_or_val_name_p >>= \lit_or_val_name ->
  string " ->" >> space_or_spicy_nl >>
  value_expression_p >>= \value_expression ->
  return $ Case lit_or_val_name value_expression
  :: Parser Case

-- DefaultCase: default_case_p

default_case_p =
  spicy_new_line >> string "... ->" >> space_or_spicy_nl >>
  value_expression_p >>= \value_expr ->
  return $ DefaultCase value_expr
  :: Parser DefaultCase

-- CasesExpr: cases_p

cases_p =
  string "cases" >> specific_case_p >>= \case1 ->
  many (try specific_case_p) >>= \cases ->
  optionMaybe (try default_case_p) >>= \maybe_default_case ->
  return $ CasesAndMaybeDefault case1 cases maybe_default_case
  :: Parser CasesExpr

-- Values: values_p, value_types_p

values_p = 
  sepBy1 value_name_p (string ", ") >>= \value_names ->
  string ": " >> value_types_p (length value_names) >>= \value_types ->
  spicy_new_line >> string "= " >>
  sepBy1 value_expression_p (string ", ") >>= \value_expressions ->
  case length value_types /= length value_names of 
    True -> 
      parserFail "names and types don't match in numbers"
    False -> case length value_expressions /= length value_names of 
      True -> 
        parserFail "names and expressions don't match in numbers"
      False ->
        return $ NamesTypesAndExpressions value_names value_types value_expressions
  :: Parser Values

value_types_p = ( \value_names_length ->
  sepBy1 value_type_p (string ", ") <|>
  (string "all " *> value_type_p >>= \value_type ->
  return $ replicate value_names_length value_type)
  ) :: Int -> Parser [ ValueType ]

-- Where: where_p

where_p = 
  string "let" >> spicy_new_line >>
  many1 (try values_p <* spicy_new_lines) >>= \values ->
  string "in" >> spicy_new_line >>
  value_expression_p >>= \value_expression ->
  return $ ValueExpressionWhereValues value_expression values
  :: Parser Where

-- CasesOrWhere: cases_or_where_p

cases_or_where_p = 
  CasesExpr <$> add_pos_p cases_p <|> Where <$> where_p
  :: Parser CasesOrWhere

-- InputCasesOrWhere: input_cases_or_where_p

input_cases_or_where_p = 
  input_p >>= \input -> cases_or_where_p >>= \cases_or_where -> 
  return $ InputAndCasesOrWhere input cases_or_where
  :: Parser InputCasesOrWhere

-- ValueExpression: value_expression_p

value_expression_p =
  InputCasesOrWhere <$> try input_cases_or_where_p <|>
  CasesOrWhere <$> try cases_or_where_p <|>
  OpExpr <$> operator_expression_p
  :: Parser ValueExpression
