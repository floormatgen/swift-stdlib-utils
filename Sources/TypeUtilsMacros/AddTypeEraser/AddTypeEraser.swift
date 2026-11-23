public import SwiftSyntax
public import SwiftSyntaxMacros
import SwiftSyntaxBuilder
import SwiftDiagnostics
import _MacroUtils

public struct AddTypeEraser: PeerMacro {
  
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    
    // Ensure it is applied to a protocol decleration
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: declaration,
          message: MacroExpansionErrorMessage("Must be on a protocol declaration")))
      return []
    }
    
    // TODO: Support actors when assumeIsolated(_:file:line:) adopts typed throws
    // Make sure the protocol is not constrained to an Actor
    guard protocolDecl.typeConstraint != .Actor else {
      context.diagnose(
        Diagnostic(
          node: declaration,
          message: MacroExpansionErrorMessage("Actors not currently supported")))
      return []
    }
    
    // Get the new name for the type eraser
    let (protocolName, shouldWrap) = RawIdentifiers.unwrapIdentifierIfNeeded(protocolDecl.name.text)
    var typeEraserName = "Any\(protocolName)"
    if shouldWrap {
      typeEraserName = RawIdentifiers.wrapIdentifier(typeEraserName)
    }
    
    // Generate members for the type
    let members     = try typeEraserMembers(for: protocolDecl)
    let memberBlock = MemberBlockSyntax(members: members)
    // Get access level
    let accessModifier = protocolDecl.modifiers.accessModifier
    
    // Inheritance clause for protocol conformance
    let inheritanceClause = InheritanceClauseSyntax(
      inheritedTypes: [
        InheritedTypeSyntax(
          type: IdentifierTypeSyntax(name: .identifier(protocolName))
        )
      ]
    )
    
    // Choose the best containing type
    let typeEraserDecl: DeclSyntax
    switch protocolDecl.typeConstraint {
    case .Any:
      
      // Prefer to use a struct
      var structDecl = StructDeclSyntax(
        name: .identifier(typeEraserName),
        inheritanceClause: inheritanceClause,
        memberBlock: memberBlock
      )
      if let accessModifier {
        structDecl.modifiers.insert(accessModifier, at: structDecl.modifiers.startIndex)
      }
      typeEraserDecl = DeclSyntax(structDecl)
      
    case .AnyObject:
      
      // Use a final class if protocol is constrained to AnyObject
      var classDecl = ClassDeclSyntax(
        modifiers: [
          DeclModifierSyntax(name: .keyword(.final))
        ],
        name: .identifier(typeEraserName),
        inheritanceClause: inheritanceClause,
        memberBlock: memberBlock
      )
      if let accessModifier {
        classDecl.modifiers.insert(accessModifier, at: classDecl.modifiers.startIndex)
      }
      typeEraserDecl = DeclSyntax(classDecl)
      
    case .Actor:
      preconditionFailure("Actor not supported")
    }
    
    return [
      typeEraserDecl
    ]
  }
  
}

// MARK: - Generating Members

extension AddTypeEraser {
  
  internal static func typeEraserMembers(
    for protocolDecl: ProtocolDeclSyntax
  ) throws -> MemberBlockItemListSyntax {
    var members = MemberBlockItemListSyntax()
    
    // First get access modifier for the protocol
    var accessModifier = protocolDecl.modifiers.accessModifier
    // Get the protocol type constraint
    let typeConstraint = protocolDecl.typeConstraint
    
    // If the protocol is constrained to a class, use let instead
    let bindingSpecifier: TokenSyntax
    switch typeConstraint {
    case .Any:
      bindingSpecifier = .keyword(.var)
    case .AnyObject, .Actor:
      bindingSpecifier = .keyword(.let)
    }
    
    // Do not add access modifier for members if modifier is private
    if let a = accessModifier, a.name.tokenKind == .keyword(.private) {
      accessModifier = nil
    }
    
    // Add init and base member
    let baseMember: DeclSyntax = """
      \(accessModifier)\(bindingSpecifier) base: any \(protocolDecl.name)
      """
    let initErasingMember: DeclSyntax = """
      \(accessModifier)init<T: \(protocolDecl.name.trimmed)>(erasing base: consuming T) {
          self.base = base
      }
      """
    let initMember: DeclSyntax = """
      \(accessModifier)init<T: \(protocolDecl.name.trimmed)>(_ base: consuming T) {
          self.base = base
      }
      """
    members.append(MemberBlockItemSyntax(decl: baseMember))
    members.append(MemberBlockItemSyntax(decl: initErasingMember))
    members.append(MemberBlockItemSyntax(decl: initMember))
    
    // TODO: Handle protocol requirements
    try members.append(
      contentsOf: requirementsMembers(
        for: protocolDecl.memberBlock.members,
        accessModifier: accessModifier,
        typeConstraint: typeConstraint))
    
    return members
  }
  
  private static func requirementsMembers(
    for members: some Collection<MemberBlockItemSyntax>,
    accessModifier: DeclModifierSyntax?,
    typeConstraint: ProtocolTypeConstraint
  ) throws -> [MemberBlockItemSyntax] {
    var newMembers: [MemberBlockItemSyntax] = []
    var diagnostics: [Diagnostic] = []
    
    func ensureNonStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
      if let staticModifier = modifiers.staticModifier {
        var emptyModifier = DeclModifierSyntax(name: .identifier(""))
        emptyModifier.leadingTrivia = staticModifier.leadingTrivia
        emptyModifier.trailingTrivia = staticModifier.trailingTrivia
        
        diagnostics.append(
          Diagnostic(
            node: staticModifier,
            message: MacroExpansionErrorMessage("`static` declarations are not supported"),
            fixIt: .replace(
              message: MacroExpansionFixItMessage("Remove `static` from the declaration"),
              oldNode: staticModifier,
              newNode: emptyModifier)))
        return false
      }
      return true
    }
    
    for member in members {
      if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
        assert(funcDecl.body == nil, "Protocol decl should not have implementation")
        guard ensureNonStatic(funcDecl.modifiers) else { continue }
      } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
        guard ensureNonStatic(varDecl.modifiers) else { continue }
      } else if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
        assert(initDecl.body == nil, "Protocol decl should not have implementation")
        
        var emptyDecl = "" as DeclSyntax
        emptyDecl.leadingTrivia = initDecl.leadingTrivia
        emptyDecl.trailingTrivia = initDecl.trailingTrivia
        
        // Init requirements are not allowed, they can't be satisfied by a type-erasing wrapper
        diagnostics.append(
          Diagnostic(
            node: member,
            message: MacroExpansionErrorMessage("`init` declarations are not supported"),
            fixIt: .replace(
              message: MacroExpansionFixItMessage("Remove `init` requirement"),
              oldNode: member,
              newNode: emptyDecl)))
      }
    }
    
    // Make sure we have not run into any restrictions
    guard diagnostics.isEmpty else {
      throw DiagnosticsError(diagnostics: diagnostics)
    }
    
    return newMembers
  }
}
