part of 'ai_assist_registry.dart';

enum AiPromptDelivery { argv, stdin, promptFile }

enum AiNativeStructuredOutput {
  none,
  codexSchemaFile,
  claudeJsonSchema,
  jsonSchemaArgument,
}
