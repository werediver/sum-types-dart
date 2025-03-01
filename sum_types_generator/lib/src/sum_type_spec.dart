import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:source_gen/source_gen.dart';
import 'package:sum_types/sum_types.dart';
import 'package:sum_types_generator/src/common_spec.dart';

@immutable
class SumTypeSpec {
  const SumTypeSpec({
    required this.sumTypeName,
    required this.sumTypeBaseName,
    required this.recordIfaceName,
    required this.typeParams,
    required this.cases,
    required this.noPayloadTypeInstance,
  });

  final String sumTypeName;
  final String sumTypeBaseName;
  final String recordIfaceName;
  final Iterable<TypeParamSpec> typeParams;
  final Iterable<CaseSpec> cases;
  final String noPayloadTypeInstance;
}

@immutable
class CaseSpec {
  const CaseSpec({
    required this.name,
    required this.type,
    required this.parameterStyle,
    required this.parameterName,
  });

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CaseSpec &&
      other.name == name &&
      other.type == type &&
      other.parameterStyle == parameterStyle &&
      other.parameterName == parameterName;

  @override
  int get hashCode {
    var result = 17;
    result = 37 * result + name.hashCode;
    result = 37 * result + type.hashCode;
    result = 37 * result + parameterStyle.hashCode;
    result = 37 * result + parameterName.hashCode;
    return result;
  }

  final String name;
  final CaseTypeSpec type;
  final ParameterStyle parameterStyle;
  final String parameterName;
}

enum ParameterStyle { positional, named }

@immutable
class CaseTypeSpec {
  const CaseTypeSpec({
    required this.name,
    required this.requiresPayload,
    required this.isDirectlyRecursive,
  });

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CaseTypeSpec &&
      other.name == name &&
      other.requiresPayload == requiresPayload &&
      other.isDirectlyRecursive == isDirectlyRecursive;

  @override
  int get hashCode {
    var result = 17;
    result = 37 * result + name.hashCode;
    result = 37 * result + requiresPayload.hashCode;
    result = 37 * result + isDirectlyRecursive.hashCode;
    return result;
  }

  final String name;
  final bool requiresPayload;
  final bool isDirectlyRecursive;
}

SumTypeSpec makeSumTypeSpec(Element element, ConstantReader annotation) {
  final noPayloadTypeName = "$Unit";
  final noPayloadTypeInstance = "const $noPayloadTypeName()";

  if (element is ClassElement &&
      element is! MixinElement &&
      element is! EnumElement) {
    final importPrefixes = Map.fromEntries(
      element.library.prefixes.expand(
        (o) => o.imports
            .map((import) =>
                import.importedLibrary?.location?.components.firstOrNull)
            .nonNulls
            .map((importLocation) => MapEntry(importLocation, o.name)),
      ),
    );

    final sumTypeName = element.name;
    CaseTypeSpec __makeCaseTypeSpec(DartType? type) => _makeCaseTypeSpec(
          declaredCaseType: type,
          sumTypeName: sumTypeName,
          noPayloadTypeName: noPayloadTypeName,
          importPrefixes: importPrefixes,
        );
    CaseSpec __makeCaseSpec(ConstructorElement ctor) =>
        _makeCaseSpec(ctor, makeCaseTypeSpec: __makeCaseTypeSpec);

    return SumTypeSpec(
      sumTypeName: sumTypeName,
      sumTypeBaseName: "_\$$sumTypeName",
      recordIfaceName: "${sumTypeName}RecordBase",
      typeParams: element.typeParameters.map(
        (e) => TypeParamSpec(
          name: e.name,
          bound: e.bound?.element?.name,
        ),
      ),
      cases: element.constructors
          .where((ctor) => ctor.name.isNotEmpty && !ctor.isFactory)
          .map(__makeCaseSpec),
      noPayloadTypeInstance: noPayloadTypeInstance,
    );
  }
  throw Exception("A sum-type anchor must be a class");
}

CaseSpec _makeCaseSpec(
  ConstructorElement ctor, {
  required CaseTypeSpec Function(DartType?) makeCaseTypeSpec,
}) {
  if (ctor.parameters.length <= 1) {
    final ParameterStyle style;
    final name = ctor.parameters.isNotEmpty ? ctor.parameters.single.name : "";
    final caseType =
        ctor.parameters.isNotEmpty ? ctor.parameters.single.type : null;

    if (ctor.parameters.isNotEmpty && ctor.parameters.single.isNamed) {
      style = ParameterStyle.named;
    } else {
      style = ParameterStyle.positional;
    }

    return CaseSpec(
      name: ctor.name,
      type: makeCaseTypeSpec(caseType),
      parameterStyle: style,
      parameterName: name,
    );
  }
  throw Exception(
    "Case-constructor ${ctor.name} shall have at most one parameter",
  );
}

CaseTypeSpec _makeCaseTypeSpec({
  DartType? declaredCaseType,
  required String sumTypeName,
  required String noPayloadTypeName,
  required Map<String, String>? importPrefixes,
}) {
  if (declaredCaseType != null) {
    final resolvedTypeName = _resolveTypeName(
      declaredCaseType,
      importPrefixes: importPrefixes,
    );
    return CaseTypeSpec(
      name: resolvedTypeName,
      requiresPayload: true,
      isDirectlyRecursive: resolvedTypeName == sumTypeName,
    );
  } else {
    return CaseTypeSpec(
      name: noPayloadTypeName,
      requiresPayload: false,
      isDirectlyRecursive: false,
    );
  }
}

String _resolveTypeName(
  DartType type, {
  String Function(DartType)? name,
  Map<String, String>? importPrefixes,
}) {
  final _name = name ??
      (type) {
        final prefix =
            importPrefixes?[type.element?.library?.location?.components.first];
        return [
          if (prefix != null) "$prefix.",
          type.getDisplayString(
            // Newer versions of "analyzer" (somewhere after 6.0.0) declare `withNullability`
            // deprecated (and locked to `true`), but older versions require it.
            // ignore: deprecated_member_use
            withNullability: true,
          ),
        ].join();
      };
  return _name(type);
}
