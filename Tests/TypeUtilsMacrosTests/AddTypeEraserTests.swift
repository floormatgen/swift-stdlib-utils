import XCTest
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import SwiftSyntaxMacrosGenericTestSupport
import TypeUtilsMacros

final class AddTypeEraserTests: XCTestCase {
  
  let testMacros: [String : any Macro.Type] = [
    "AddTypeEraser": AddTypeEraser.self
  ]
  
  // MARK: - Utilities
  
  func makeDiagnosticSpecForStaticDecl(
    line: Int,
    column: Int,
    originatorFileID: StaticString = #fileID,
    originatorFile: StaticString = #filePath,
    originatorLine: UInt = #line,
    originatorColumn: UInt = #column
  ) -> DiagnosticSpec {
    DiagnosticSpec(
      message: "`static` declarations are not supported",
      line: line,
      column: column,
      fixIts: [
        FixItSpec(message: "Remove `static` from the declaration"),
      ],
      originatorFileID: originatorFileID,
      originatorFile: originatorFile,
      originatorLine: originatorLine,
      originatorColumn: originatorColumn)
  }
  
  func makeDiagnosticSpecForInitDecl(
    line: Int,
    column: Int,
    originatorFileID: StaticString = #fileID,
    originatorFile: StaticString = #filePath,
    originatorLine: UInt = #line,
    originatorColumn: UInt = #column
  ) -> DiagnosticSpec {
    DiagnosticSpec(
      message: "`init` declarations are not supported",
      line: line,
      column: column,
      fixIts: [
        FixItSpec(message: "Remove `init` requirement"),
      ],
      originatorFileID: originatorFileID,
      originatorFile: originatorFile,
      originatorLine: originatorLine,
      originatorColumn: originatorColumn)
  }
  
  // MARK: - Tests
  
  func test_emptyProtocol() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      protocol Foo {
      }
      """,
      expandedSource: """
      protocol Foo {
      }
      
      struct AnyFoo: Foo {
          var base: any Foo
          init<T: Foo>(erasing base: consuming T) {
              self.base = base
          }
          init<T: Foo>(_ base: consuming T) {
              self.base = base
          }
      }
      """,
      macros: testMacros
    )
  }
  
  func test_emptyPublicProtocol() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      public protocol Foo {
      }
      """,
      expandedSource: """
      public protocol Foo {
      }
      
      public struct AnyFoo: Foo {
          public var base: any Foo
          public init<T: Foo>(erasing base: consuming T) {
              self.base = base
          }
          public init<T: Foo>(_ base: consuming T) {
              self.base = base
          }
      }
      """,
      macros: testMacros
    )
  }
  
  func test_packageClassBoundProtocol() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      package protocol Foo: AnyObject {
      }
      """,
      expandedSource: """
      package protocol Foo: AnyObject {
      }
      
      package final class AnyFoo: Foo {
          package let base: any Foo
          package init<T: Foo>(erasing base: consuming T) {
              self.base = base
          }
          package init<T: Foo>(_ base: consuming T) {
              self.base = base
          }
      }
      """,
      macros: testMacros
    )
  }
  
  func test_privateClassBoundProtocol() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      private protocol Foo: AnyObject {
      }
      """,
      expandedSource: """
      private protocol Foo: AnyObject {
      }
      
      private final class AnyFoo: Foo {
          let base: any Foo
          init<T: Foo>(erasing base: consuming T) {
              self.base = base
          }
          init<T: Foo>(_ base: consuming T) {
              self.base = base
          }
      }
      """,
      macros: testMacros
    )
  }
  
  func test_staticFunctionNotAllowed() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      protocol Foo {
        static func bar()
      }
      """,
      expandedSource: """
      protocol Foo {
        static func bar()
      }
      """,
      diagnostics: [
        makeDiagnosticSpecForStaticDecl(line: 3, column: 3),
      ],
      macros: testMacros
    )
  }
  
  func test_staticVariablesNotAllowed() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      internal protocol Foo: AnyObject {
        static var foo: String { get }
        static var bar: Int { get set }
      }
      """,
      expandedSource: """
      internal protocol Foo: AnyObject {
        static var foo: String { get }
        static var bar: Int { get set }
      }
      """,
      diagnostics: [
        makeDiagnosticSpecForStaticDecl(line: 3, column: 3),
        makeDiagnosticSpecForStaticDecl(line: 4, column: 3),
      ],
      macros: testMacros
    )
  }
  
  func test_initNotAllowed() {
    assertMacroExpansion(
      """
      @AddTypeEraser
      fileprivate protocol Foo: Any {
        init()
        init(foo: Int)
        init(foo: Int, _ bar: String)
      }
      """,
      expandedSource: """
      fileprivate protocol Foo: Any {
        init()
        init(foo: Int)
        init(foo: Int, _ bar: String)
      }
      """,
      diagnostics: [
        makeDiagnosticSpecForInitDecl(line: 3, column: 3),
        makeDiagnosticSpecForInitDecl(line: 4, column: 3),
        makeDiagnosticSpecForInitDecl(line: 5, column: 3),
      ],
      macros: testMacros
    )
  }
  
}
