import core, location, operator, types, type_env, triplet
import strutils, sequtils, tables

type
  DebugFlag* = distinct bool

  NodeKind* = enum AProgram, AGroup, ARecord, AEnum, AData, AField, AInstance, AIField, ADataInstance, ABranch, AInt, AEnumValue, AFloat, ABool, ACall, AFunction, ALabel, AString, AChar, APragma, AList, AArray, AOperator, AType, AReturn, AIf, AForEach, AAssignment, ADefinition, AMember, AIndex, AIndexAssignment, APointer, ADeref, ADataIndex, AImport, AMacro, AMacroInvocation

  BNode* = object of RootObj
    location*: Location
    case kind*: NodeKind:
    of AProgram:
      name*:          string
      imports*:       seq[Node]
      definitions*:   seq[Node]
      functions*:     seq[Node]
      predefined*:    seq[Predefined]
    of AGroup:
      nodes*:         seq[Node]
    of ARecord:
      rLabel*:        string
      fields*:        seq[Node]
    of AEnum:
      eLabel*:        string
      variants*:      seq[string]
    of AData:
      dLabel*:        string
      branches*:      seq[Node]
    of AField:
      fieldLabel*:    string
      fieldType*:     Type
    of AInstance:
      iLabel*:        string
      iFields*:       seq[Node]
    of AIField:
      iFieldLabel*:   string
      iFieldValue*:   Node
    of ADataInstance:
      en*:            string
      enArgs*:        seq[Node]
      enGeneric*:     seq[Type]
    of ABranch:
      bKind*:         string
      bTypes*:        seq[Type]
    of AInt:
      value*:         int
    of AEnumValue:
      e*:             string
      eValue*:        int
    of AFloat:
      f*:             float
    of ABool:
      b*:             bool
    of ACall:
      function*:      Node
      args*:          seq[Node]
    of AFunction:
      label*:         string
      params*:        seq[string]
      types*:         Type
      code*:          Node
    of ALabel, AString, APragma:
      s*:             string
    of AChar:
      c*:             char
    of AList:
      lElements*:     seq[Node]
    of AArray:
      elements*:      seq[Node]
    of AOperator:
      op*:            Operator
    of AType:
      typ*:           Type
    of AReturn:
      ret*:           Node
    of AIf:
      condition*:     Node
      success*:       Node
      fail*:          Node
    of AForEach:
      iter*:          string
      forEachIndex*:  string
      forEachSeq*:    Node
      forEachBlock*:  Node
    of AAssignment:
      target*:        string
      res*:           Node
      isDeref*:       bool
    of ADefinition:
      id*:            string
      definition*:    Node
    of AMember:
      receiver*:      Node
      member*:        string
    of AIndex:
      indexable*:     Node
      index*:         Node
    of AIndexAssignment:
      aIndex*:        Node
      aValue*:        Node
    of APointer:
      targetObject*:  Node
    of ADeref:
      derefedObject*: Node
    of ADataIndex:
      data*:          Node
      dataIndex*:     int
    of AImport:
      importLabel*:   string
      importAliases*: seq[string]
    of AMacro:
      macroLabel*:    string
      macroArgs*:     seq[string]
      macroBlock*:    Node
      macroFunction*: TripletFunction
      hasBlock*:      bool
    of AMacroInvocation:
      aName*:         string
      iArgs*:         seq[Node]
      iBlock*:        Node
    tag*:             Type

  Node* = ref BNode

  NodeModule = enum MLib, MNative, MNim


let OPERATOR_SYMBOLS*: array[Operator, string] = [
  "and",  # OpAnd
  "or",   # OpOr
  "==",   # OpEq
  "%",    # OpMod
  "+",    # OpAdd
  "-",    # OpSub
  "*",    # OpMul
  "/",    # OpDiv
  "!=",   # OpNotEq
  ">",    # OpGt
  ">=",   # OpGte
  "<",    # OpLt
  "<=",   # OpLte
  "^",    # OpXor
  "not",  # OpNot
  "@"     # OpAt
]


proc `$`*(node: Node): string

var names*: Table[int, string] = initTable[int, string]()

proc `$`*(location: Location): string =
  result = "$1:$2($3)" % [$location.line, $location.column, names[location.fileId]]

proc render*(node: Node, depth: int): string =
  var value: string
  if node == nil:
    value = "nil"
  else:
    value = case node.kind:
    of AProgram:
      "AProgram($1):\n$2\n$3" % [$node.name, node.definitions.mapIt(render(it, 1)).join("\n"), node.functions.mapIt(render(it, 1)).join("\n")]
    of AGroup:
      "AGroup:\n$1" % node.nodes.mapIt(render(it, depth + 1)).join("\n")
    of ARecord:
      "ARecord($1):\n$2" % [node.rLabel, node.fields.mapIt(render(it, 2)).join("\n")]
    of AEnum:
      "AEnum($1):\n$2" % [node.eLabel, node.variants.mapIt("    $2" % it).join("\n")]
    of AData:
      "AData($1):\n$2" % [node.dLabel, node.branches.mapIt(render(it, depth + 1)).join("\n")]
    of AField:
      "AField($1$2)" % [node.fieldLabel, $node.fieldType]
    of AInstance:
      "AInstance($1):\n$2" % [node.iLabel, node.iFields.mapIt(render(it, depth + 1)).join("\n")]
    of AIField:
      "AIField($1 $2)" % [node.iFieldLabel, render(node.iFieldValue, 0)]
    of ADataInstance:
      "ADataInstance($1):\n$2" % [node.en, node.enArgs.mapIt(render(it, depth + 1)).join("\n")]
    of ABranch:
      "ABranch($1 $2)" % [node.bKind, node.bTypes.mapIt($it).join(" ")]
    of AInt:
      "AInt($1)" % $node.value
    of AEnumValue:
      "AEnumValue($1)" % node.e
    of AFloat:
      "AFloat($1)" % $node.f
    of ABool:
      "ABool($1)" % $node.b
    of ACall:
      var typ = if node.tag == nil: "" else: " #$1" % $node.tag
      "ACall($1$2):\n$3" % [render(node.function, 0), typ, (if len(node.args) == 0: "[]" else: node.args.mapIt(render(it, depth + 1)).join("\n"))]
    of AFunction:
      "AFunction($1):\n$2params:\n$3\n$2types:\n$4\n$2code:\n$5" % [
        node.label,
        repeat("  ", depth + 1),
        node.params.mapIt(repeat("  ", depth + 2) & it).join("\n"),
        render(node.types, depth + 2),
        render(node.code, depth + 2)
      ]
    of ALabel:
      var typ = if node.tag == nil: "" else: " #$1" % $node.tag
      "ALabel($1$2)" % [node.s, typ]
    of AString:
      "AString('$1')" % node.s
    of APragma:
      "APragma($1)" % node.s
    of AChar:
      "AChar($1)" % $node.c
    of AList:
      "AList($1)" % node.lElements.mapIt(render(it, depth + 1).strip(leading=true)).join(" ")
    of AArray:
      "AArray($1)" % node.elements.mapIt(render(it, depth + 1).strip(leading=true)).join(" ")
    of AOperator:
      "AOperator($1)" % $node.op
    of AType:
      "AType($1)" % $node.typ
    of AReturn:
      "AReturn($1)" % render(node.ret, depth + 1).strip(leading=true)
    of AIf:
      "AIf($1):\n$2success:\n$3\n$2fail:\n$4" % [
        render(node.condition, 0),
        repeat("  ", depth + 1),
        render(node.success, depth + 2),
        render(node.fail, depth + 2)
      ]
    of AForEach:
      "AForEach($1$2 in $3):\n$4" % [
        if len(node.forEachIndex) > 0: "$1 " % node.forEachIndex else: "",
        node.iter,
        render(node.forEachSeq, 0),
        render(node.forEachBlock, depth + 1)
      ]
    of AAssignment:
      "AAssignment($1):\n$2" % [node.target, render(node.res, depth + 1)]
    of ADefinition:
      "ADefinition($1):\n$2" % [node.id, render(node.definition, depth + 1)]
    of AMember:
      "AMember($1 $2)" % [render(node.receiver, 0), node.member]
    of AIndex:
      "AIndex($1 $2)" % [render(node.indexable, depth + 1).strip(leading=true), render(node.index, 0)]
    of AIndexAssignment:
      "AIndexAssignment($1):\n$2" % [render(node.aIndex, depth + 1).strip(leading=true), render(node.aValue, depth + 1)]
    of APointer:
      "APointer($1)" % [render(node.targetObject, 0)]
    of ADeref:
      "ADeref($1)" % [render(node.derefedObject, 0)]
    of ADataIndex:
      "ADataIndex($1 $2)" % [render(node.data, 0), $node.dataIndex]
    of AImport:
      "AImport($1 $2)" % [node.importLabel, node.importAliases.join(" ")]
    of AMacro:
      "AMacro($1)" % node.macroLabel
    of AMacroInvocation:
      "AMacroInvocation($1):\n$2" % [node.aName, node.iArgs.mapIt(render(it, depth + 1)).join("\n")]
    else: ""

  result = repeat("  ", depth) & value


proc `$`*(node: Node): string =
  result = render(node, 0)

iterator mitems*(range: Node): var Node =
  case range.kind:
  of AProgram:
    for f in range.functions.mitems: yield f
  of AGroup:
    for n in range.nodes.mitems: yield n
  of ARecord:
    for f in range.fields.mitems: yield f
  of AInstance:
    for i in range.iFields.mitems: yield i
  of AIField:
    yield range.iFieldValue
  of ADataInstance:
    for e in range.enArgs.mitems: yield e
  of ACall:
    yield range.function
    for a in range.args.mitems: yield a
  of AFunction:
    yield range.code
  of AList:
    for l in range.lElements.mitems: yield l
  of AArray:
    for e in range.elements.mitems: yield e
  of AReturn:
    yield range.ret
  of AIf:
    yield range.condition
    yield range.success
    if range.fail != nil:
      yield range.fail
  of AForEach:
    yield range.forEachSeq
    yield range.forEachBlock
  of AAssignment:
    yield range.res
  of ADefinition:
    yield range.definition
  of AMember:
    yield range.receiver
  of AIndex:
    yield range.indexable
    yield range.index
  of AIndexAssignment:
    yield range.aIndex
    yield range.aValue
  of APointer:
    yield range.targetObject
  of ADeref:
    yield range.derefedObject
  else:
    discard

