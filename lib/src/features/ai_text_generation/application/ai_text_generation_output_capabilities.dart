part of 'ai_text_generation_registry.dart';

enum AiPromptDelivery { argv, stdin, promptFile }

enum AiNativeStructuredOutput {
  none,
  codexSchemaFile,
  claudeJsonSchema,
  jsonSchemaArgument,
}
