{-# LANGUAGE LambdaCase #-}

module CodeGenerators.ValueExpressions where

import Prelude
  ( String, Int, (>>=), (>>), (-), (+), (*), (++), ($), undefined, map, concat, foldl
  , return, error, fmap, mapM, init, last )
import Data.List ( intercalate, replicate )
import Control.Monad.State ( State, get, put, modify )

import Helpers ( (-->), (.>) )

import Parsers.LowLevel ( ApplicationDirection( LeftApplication, RightApplication ) )
import Parsers.ValueExpressions
  ( ParenthesisExpression( ForPrecedence, Tuple )
  , HighPrecedenceExpression( Parenthesis, Atomic )
  , ApplicationExpression( Application )
  , MultiplicationFactor( ApplicationMF, HighPrecedenceMF )
  , MultiplicationExpression( Multiplication )
  , SubtractionFactor( MultiplicationSF, ApplicationSF, HighPrecedenceSF )
  , SubtractionExpression( Subtraction )
  , SpecificCaseExpression( SpecificCase )
  , CasesExpression( Cases )
  , NameTypeAndValueExpression( NameTypeAndValue )
  , NameTypeAndValueExpressions( NameTypeAndValueExps )
  , IntermediatesOutputExpression( IntermediatesOutputExpression )
  , AbstractionArgumentExpression( Name, TupleMatching )
  , NoAbstractionsValueExpression
    ( SubtractionExp, MultiplicationExp, ApplicationExp, HighPrecedenceExp, CasesExp
    , IntermediatesOutputExp )
  , ValueExpression(Value)
  )

import CodeGenerators.LowLevel
  ( tuple_matching_expression_g, name_expression_g, type_expression_g
  , atomic_expression_g )

{- 
All:
ParenthesisExpression, HighPrecedenceExpression, ApplicationExpression
MultiplicationFactor, MultiplicationExpression, SubtractionFactor, SubtractionExpression
SpecificCaseExpression, CasesExpression
NameTypeAndValueExpression, NameTypeAndValueExpressions, IntermediatesOutputExpression
AbstractionArgument, NoAbstractionsValueExpression, ValueExpression
-}

type IndentState = State Int
type HSSource = String

indent = ( \i -> replicate (2 * i) ' ' )
  :: Int -> String

-- ParenthesisExpression

parenthesis_expression_g = ( \case
  ForPrecedence ve -> value_expression_g ve >>= ("(" ++) .> (++ ")") .> return
  Tuple ves -> 
    mapM value_expression_g ves >>= \l ->
    return $ "( " ++ init l-->map (++ ", ")-->concat ++ l-->last ++ " )"
  ) :: ParenthesisExpression -> IndentState HSSource

-- HighPrecedenceExpression

high_precedence_expression_g = ( \case
  Parenthesis pe -> parenthesis_expression_g pe
  Atomic ae -> return $ atomic_expression_g ae
  ) :: HighPrecedenceExpression -> IndentState HSSource

-- ApplicationExpression

application_direction_g = ( \generate_so_far -> \generate_hpe -> \ad ->
  generate_so_far >>= \gsf ->
  generate_hpe >>= \hpe -> case ad of
    LeftApplication -> return $ gsf ++ " " ++ hpe
    RightApplication -> return $ hpe ++ " " ++ gsf
  ) :: IndentState HSSource -> IndentState HSSource -> ApplicationDirection
         -> IndentState HSSource

application_expression_g = ( \(Application hpe_ad_s hpe) ->
  let
  hpe_generated_ad_s =
    map ( \( hpe, ad ) -> ( high_precedence_expression_g hpe, ad ) ) hpe_ad_s
    :: [ ( IndentState HSSource, ApplicationDirection ) ]
  application_expression_help_g = ( \case
    [] -> error "application expression should have at least one application direction"
    [ ( generate_so_far, ad ) ] ->
      application_direction_g generate_so_far (high_precedence_expression_g hpe) ad
    ( generate_so_far, ad1 ):( hpe_generated, ad2 ):the_rest ->
      let
      generated_so_far_next = application_direction_g generate_so_far hpe_generated ad1
        :: IndentState HSSource
      in
      application_expression_help_g $ ( generated_so_far_next, ad2 ):the_rest
    ) :: [ ( IndentState HSSource, ApplicationDirection ) ] -> IndentState HSSource
  in
  application_expression_help_g hpe_generated_ad_s
  ) :: ApplicationExpression -> IndentState HSSource

-- MultiplicationFactor

multiplication_factor_g = ( \case
  ApplicationMF ae -> application_expression_g ae
  HighPrecedenceMF hpe -> high_precedence_expression_g hpe
  ) :: MultiplicationFactor -> IndentState HSSource

-- MultiplicationExpression

multiplication_expression_g = ( \(Multiplication mfs) -> 
  mapM multiplication_factor_g mfs >>= intercalate " * " .> return
  ) :: MultiplicationExpression -> IndentState HSSource

-- SubtractionFactor

subtraction_factor_g = ( \case
  MultiplicationSF me -> multiplication_expression_g me
  ApplicationSF ae -> application_expression_g ae
  HighPrecedenceSF hpe -> high_precedence_expression_g hpe
  ) :: SubtractionFactor -> IndentState HSSource

-- SubtractionExpression

subtraction_expression_g = ( \(Subtraction sf1 sf2) ->
  subtraction_factor_g sf1 >>= \sf1_g ->
  subtraction_factor_g sf2 >>= \sf2_g ->
  return $ sf1_g ++ " - " ++ sf2_g
  ) :: SubtractionExpression -> IndentState HSSource

-- SpecificCaseExpression

specific_case_expression_g = ( \(SpecificCase ae ve) ->
  value_expression_g ve >>= \ve_g ->
  get >>= \num ->
  return $ indent num ++ atomic_expression_g ae ++ " -> " ++ ve_g
  ) :: SpecificCaseExpression -> IndentState HSSource

-- CasesExpression

cases_expression_g = ( \(Cases sces) ->
  modify (+ 1) >>
  (sces-->mapM specific_case_expression_g) >>= \sces_g ->
  modify (\i -> i - 1) >>
  ("\\case\n" ++ init sces_g-->map (++ "\n")-->(++ [last sces_g])-->concat)-->return
  ) :: CasesExpression -> IndentState HSSource

-- NameTypeAndValueExpression

name_type_and_value_expression_g = ( \(NameTypeAndValue ne te ve) -> 
  value_expression_g ve >>= \ve_g ->
  get >>= \num ->
  let
  combine value_begin value_end =
    indent num  ++ name_expression_g ne ++ " = " ++
    value_begin ++ ve_g ++ value_end ++ "\n" ++
    indent (num + 1) ++ ":: " ++ type_expression_g te ++ "\n"
  in
  return $ case ve of
    (Value [] nae) -> combine "" ""
    _ -> combine "( " " )"
  ) :: NameTypeAndValueExpression -> IndentState HSSource

-- NameTypeAndValueExpressions

name_type_and_value_expressions_g = ( \(NameTypeAndValueExps ntaves) ->
  ntaves-->mapM name_type_and_value_expression_g >>= concat .> return
  ) :: NameTypeAndValueExpressions -> IndentState HSSource

-- IntermediatesOutputExpression

intermediates_output_expression_g = ( \(IntermediatesOutputExpression ntaves ve) ->
  modify (+ 1) >> get >>= \num ->
  name_type_and_value_expressions_g ntaves >>= \ntaves_g ->
  value_expression_g ve >>= \ve_g ->
  modify (\i -> i - 1) >>
  ("\n" ++ indent num ++ "let\n" ++ ntaves_g ++ indent num ++ "in\n" ++ indent num ++
   ve_g)-->return
  ) :: IntermediatesOutputExpression -> IndentState HSSource

-- AbstractionArgumentExpression

abstraction_argument_expression_g = ( \case
  Name n -> name_expression_g n
  TupleMatching tm -> tuple_matching_expression_g tm
  ) :: AbstractionArgumentExpression -> String

-- NoAbstractionsValueExpression

no_abstraction_expression_g = ( \case
    SubtractionExp se -> subtraction_expression_g se
    MultiplicationExp me -> multiplication_expression_g me
    ApplicationExp ae -> application_expression_g ae
    HighPrecedenceExp hpe -> high_precedence_expression_g hpe
    CasesExp ce -> cases_expression_g ce
    IntermediatesOutputExp ioe -> intermediates_output_expression_g ioe 
  ) :: NoAbstractionsValueExpression -> IndentState HSSource

-- ValueExpression

value_expression_g = ( \(Value aaes nae) ->
  no_abstraction_expression_g nae >>= \nae_g ->
  aaes-->map ( abstraction_argument_expression_g .> ("\\" ++) .> (++ " -> "))-->concat
    -->(++ nae_g)-->return
  ) :: ValueExpression -> IndentState HSSource
