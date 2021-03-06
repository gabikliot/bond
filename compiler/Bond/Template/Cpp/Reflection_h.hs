-- Copyright (c) Microsoft. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for full license information.

{-# LANGUAGE QuasiQuotes, OverloadedStrings, RecordWildCards #-}

module Bond.Template.Cpp.Reflection_h (reflection_h) where

import System.FilePath
import Data.Monoid
import Data.Text.Lazy (Text)
import Text.Shakespeare.Text
import Bond.Schema
import Bond.Template.TypeMapping
import Bond.Template.Util
import qualified Bond.Template.Cpp.Util as CPP

-- generate the *_refection.h file from parsed .bond file
reflection_h :: MappingContext -> String -> [Import] -> [Declaration] -> (String, Text)
reflection_h cpp file imports declarations = ("_reflection.h", [lt|
#pragma once

#include "#{file}_types.h"
#include <bond/core/reflection.h>
#{newlineSepEnd 0 include imports}
#{CPP.openNamespace cpp}
    #{doubleLineSepEnd 1 schema declarations}
#{CPP.closeNamespace cpp}
|])
  where
    idlNamespace = getIdlQualifiedName $ getIdlNamespace cpp

    -- C++ type
    cppType = getTypeName cpp

    -- template for generating #include statement from import
    include (Import path) = [lt|#include "#{dropExtension path}_reflection.h"|]

    -- template for generating struct schema
    schema s@Struct {..} = [lt|//
    // #{declName}
    //
    #{CPP.template s}struct #{structName}::Schema
    {
        typedef #{baseType structBase} base;

        static const bond::Metadata metadata;
        #{newlineBeginSep 2 fieldMetadata structFields}

        public: struct var
        {#{fieldTemplates}};

        private: typedef boost::mpl::list<> fields0;
        #{newlineSep 2 pushField indexedFields}

        public: typedef #{typename}fields#{length structFields}::type fields;
        #{constructor}
        
        static bond::Metadata GetMetadata()
        {
            return bond::reflection::MetadataInit#{metadataInitArgs}("#{declName}", "#{idlNamespace}.#{declName}",
                #{CPP.attributeInit declAttributes}
            );
        }
    };
    #{onlyTemplate $ CPP.schemaMetadata cpp s}|]
      where
        structParams = CPP.structParams s

        structName = CPP.structName s

        onlyTemplate x = if null declParams then mempty else x

        metadataInitArgs = onlyTemplate [lt|<boost::mpl::list#{structParams} >|]

        typename = onlyTemplate [lt|typename |]

        -- constructor, generated only for struct templates
        constructor = onlyTemplate [lt|
        Schema()
        {
            // Force instantiation of template statics
            (void)metadata;
            #{newlineSep 3 static structFields}
        }|]
          where
            static Field {..} = [lt|(void)s_#{fieldName}_metadata;|]
        
        -- reversed list of field names zipped with indexes
        indexedFields :: [(String, Int)]
        indexedFields = zipWith ((,) . fieldName) (reverse structFields) [0..]

        baseType (Just base) = cppType base
        baseType Nothing = "bond::no_base"

        pushField (field, i) =
            [lt|private: typedef #{typename}boost::mpl::push_front<fields#{i}, #{typename}var::#{field}>::type fields#{i + 1};|]

        fieldMetadata Field {..} =
            [lt|private: static const bond::Metadata s_#{fieldName}_metadata;|]

        fieldTemplates = mconcatFor structFields $ \ f@Field {..} -> [lt|
            // #{fieldName}
            typedef bond::reflection::FieldTemplate<
                #{fieldOrdinal},
                #{CPP.modifierTag f},
                #{structName},
                #{cppType fieldType},
                &#{structName}::#{fieldName},
                &s_#{fieldName}_metadata
            > #{fieldName};
        |]


    -- nothing to generate for enums
    schema _ = mempty
