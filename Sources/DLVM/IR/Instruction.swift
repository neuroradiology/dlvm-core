//
//  Instruction.swift
//  DLVM
//
//  Copyright 2016-2017 Richard Wei.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreTensor
import CoreOp

// MARK: - Core Instruction Set
public enum InstructionKind {
    /** Control flow **/
    /// Unconditionally branch to basic block
    case branch(BasicBlock, [Use])
    /// Conditional branch depending on the value
    case conditional(Use, BasicBlock, [Use], BasicBlock, [Use])
    /// Return
    case `return`(Use?)

    /** Literal constructor **/
    case literal(Literal, Type)

    /** Operators **/
    /// Elementwise numeric unary operation (map)
    case numericUnary(NumericUnaryOp, Use)
    /// Elementwise numeric binary operation (zipWith)
    case numericBinary(NumericBinaryOp, Use, Use)
    /// Elementwise binary boolean operation
    case booleanBinary(BooleanBinaryOp, Use, Use)
    /// Negation
    case not(Use)
    /// Comparison
    case compare(ComparisonOp, Use, Use)
    /// Data type cast operation
    case dataTypeCast(Use, DataType)
    /// Scan operation
    case scan(ReductionCombinator, Use, [Int])
    /// Reduction operation
    case reduce(ReductionCombinator, Use, initial: Use, [Int])
    /// vector dot, matrix-vector multiplication and matrix-matrix multiplication
    case dot(Use, Use)
    /// Concatenation operation
    case concatenate([Use], axis: Int)
    /// Transpose
    case transpose(Use)
    /// Slice
    case slice(Use, at: CountableClosedRange<Int>)
    /// Shuffle
    case random(TensorShape, from: Use, upTo: Use)
    /// Select
    case select(Use, Use, by: Use)
    /// Convolution
    /// A convolution can be thought of as a n-dimensional window moving across a n-dimensional
    /// base area and a computation is performed for each possible position of the window.
    /// (https://www.tensorflow.org/performance/xla/operation_semantics#conv)
//    case convolve(
//        Use, // Input of rank n+2
//        kernel: Use, // Kernel weights of rank n+2
//        strides: [Int], // Kernel strides of rank n
//        padding: [(low: Int, high: Int)], // Padding of rank n
//        leftDilation: [Int], // Dilation factor of rank n
//        rightDilation: [Int] // Dilation factor of rank n
//    )
//    /// Reduce window
//    case reduceWindow(
//        ReductionCombinator, // Function or op
//        Use, // Usage
//        initial: Use, // Initial value
//        dimensions: [Int], // Window dimensions
//        strides: [Int], // Window strides
//        padding: Bool // Whether padding should be preserved
//    )

    /** Cost-free casts **/
    /// Shape cast operation
    case shapeCast(Use, TensorShape)
    /// Bitcast
    case bitCast(Use, Type)

    /** Aggregate operation **/
    /// Extract an element from tensor, tuple, or array
    case extract(from: Use, at: [ElementKey])
    /// Insert an element to tensor, tuple, or array
    case insert(Use, to: Use, at: [ElementKey])

    /** Function application **/
    case apply(Use, [Use])

    /** Memory **/
    /// Allocate host stack memory, returning a pointer
    case allocateStack(Type, Int) /// => *T
    case allocateHeap(Type, count: Use) /// => *T
    /// Reference-counted box
    case allocateBox(Type) /// => box{T}
    case projectBox(Use) /// (box{T}) => *T
    /// Retain/release a box via reference counter
    case retain(Use)
    case release(Use)
    /// Dealloc any heap memory
    case deallocate(Use)
    /// Load value from pointer on the host
    case load(Use)
    /// Store value to pointer on the host
    case store(Use, to: Use)
    /// GEP (without leading index)
    case elementPointer(Use, [ElementKey])
    /// Memory copy
    case copy(from: Use, to: Use, count: Use)
    /// Trap
    case trap
}

public final class Instruction : IRUnit, MaybeNamed {
    public typealias Parent = BasicBlock
    public var name: String?
    public var kind: InstructionKind
    public var parent: BasicBlock

    public init(name: String? = nil, kind: InstructionKind, parent: BasicBlock) {
        self.name = name
        self.kind = kind
        self.parent = parent
    }
}

extension Instruction : Value {
    public var type: Type {
        return kind.type
    }

    public var opcode: Opcode {
        return kind.opcode
    }

    public func makeUse() -> Use {
        return .instruction(type, self)
    }
}

// MARK: - Predicates
public extension InstructionKind {
    /// Returns true iff the instruction is a terminator:
    /// `branch`, `conditional` or `return`
    var isTerminator: Bool {
        switch self {
        case .branch, .conditional, .`return`:
            return true
        default:
            return false
        }
    }

    /// Returns true iff the instruction is a `return`
    var isReturn: Bool {
        switch self {
        case .`return`: return true
        default: return false
        }
    }

    /// Returns true iff the instruction is a `trap`
    var isTrap: Bool {
        switch self {
        case .trap: return true
        default: return false
        }
    }

    /// Returns true iff the instruction reads from or writes to memory
    var accessesMemory: Bool {
        switch self {
        case .allocateStack, .allocateHeap, .allocateBox,
             .projectBox, .load, .store, .deallocate:
            return true
        default:
            return false
        }
    }

    /// Returns true iff the instruction writes to memory
    var mustWriteToMemory: Bool {
        switch self {
        case .store, .copy, .deallocate: return true
        default: return false
        }
    }

    /// Returns true iff the instruction is a binary operation broadcasting
    /// two tensors of different but compatible shapes
    var isBroadcasting: Bool {
        switch self {
        case let .numericBinary(_, x, y),
             let .compare(_, x, y),
             let .booleanBinary(_, x, y):
            guard case let .tensor(s1, _) = x.type.canonical,
                  case let .tensor(s2, _) = y.type.canonical else {
                return false
            }
            return s1 != s2 && s1.isCompatible(with: s2)
        default:
            return false
        }
    }

    /// Returns true iff the instruction performs element-wise arithmetics
    /// with its operands (which are tensors)
    var isElementwiseArithmetic: Bool {
        switch self {
        case .numericUnary, .numericBinary, .compare: return true
        default: return false
        }
    }

    /// Returns true iff the instruction represets a linear transformation
    var isLinearTransformation: Bool {
        switch self {
        case .transpose, .dot: return true
        default: return false
        }
    }
}

// MARK: - Type inference
public extension InstructionKind {
    /// Infers and returns the type of the result of the instruction
    var type: Type {
        switch self {
        case let .literal(_, ty):
            return ty

        case let .numericBinary(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    NumericBinaryOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid
            
        case let .compare(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    ComparisonOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid
            
        case let .booleanBinary(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    BooleanBinaryOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid
            
        case let .not(v1):
            return v1.tensorType.flatMap { v1Ty in
                NegationOp.resultType(for: (v1Ty))
            }.map(Type.tensor) ?? .invalid

        case let .dot(v1, v2):
            guard case let .tensor(s1, t1) = v1.type.unaliased,
                  case let .tensor(s2, t2) = v2.type.unaliased,
                  let newShape = s1.matrixMultiplied(by: s2),
                  t1 == t2 else { return .invalid }
            return .tensor(newShape, t1)

        case let .numericUnary(_, v1):
            return v1.tensorType.flatMap { v1Ty in
                NumericUnaryOp.resultType(for: (v1Ty))
            }.map(Type.tensor) ?? .invalid

        case let .reduce(op, v1, initial, dims):
            let dtype: DataType
            let resultType: Type
            let dimSet = Set(dims)
            switch (op, v1.type.unaliased) {
            case let (.boolean(_), .tensor(s1, .bool))
                where dims.count <= s1.rank && dims.forAll({$0 < s1.rank}):
                dtype = .bool
                resultType = .tensor(s1.droppingDimensions(dimSet), .bool)
            case let (.numeric(_), .tensor(s1, t1))
                where t1.isNumeric && dims.count <= s1.rank && dims.forAll({$0 < s1.rank}):
                dtype = t1
                resultType = .tensor(s1.droppingDimensions(dimSet), t1)
            case let (.function(f), .tensor(s1, t1))
                where f.type.unaliased == .function([.tensor([], t1)], .tensor([], t1)):
                dtype = t1
                resultType = .tensor(s1.droppingDimensions(dimSet), t1)
            default:
                return .invalid
            }
            guard case .tensor([], dtype) = initial.type.canonical else {
                return .invalid
            }
            return resultType

        case let .scan(_, v1, _):
            guard case .tensor = v1.type.unaliased else { return .invalid }
            return v1.type

        case let .concatenate(vv, axis):
            guard let first = vv.first,
                  case let .tensor(s1, t1) = first.type.unaliased,
                  axis < s1.rank
                else { return .invalid }
            var accShape: TensorShape = s1
            for v in vv.dropFirst() {
                guard case let .tensor(shape, type) = v.type.unaliased,
                      type == t1,
                      let newShape = accShape.concatenating(with: shape, alongDimension: axis)
                    else { return .invalid }
                accShape = newShape
            }
            return .tensor(accShape, t1)

        case let .transpose(v1):
            guard case let .tensor(s1, t1) = v1.type.unaliased
                else { return .invalid }
            return .tensor(s1.transpose, t1)
        
        case let .slice(v, at: range):
            return v.type.tensorType.flatMap { tensorTy in
                SliceOp.resultType(for: (tensorTy, range))
            }.map(Type.tensor) ?? .invalid
            
        case let .random(shape, from: lo, upTo: hi):
            return lo.type.tensorType.flatMap { loTy in
                hi.type.tensorType.flatMap { hiTy in
                    RandomOp.resultType(for: (shape, loTy, hiTy))
                }
            }.map(Type.tensor) ?? .invalid
            
        case let .select(left, right, by: flags):
            return left.type.tensorType.flatMap { leftTy in
                right.type.tensorType.flatMap { rightTy in
                    flags.type.tensorType.flatMap { flTy in
                        SelectOp.resultType(for: (leftTy, rightTy, flTy))
                    }
                }
            }.map(Type.tensor) ?? .invalid
            
        case let .dataTypeCast(v1, dt):
            guard case let .tensor(s1, t1) = v1.type.unaliased, t1.canCast(to: dt) else {
                return .invalid
            }
            return .tensor(s1, dt)

        case let .shapeCast(v1, s):
            switch v1.type.unaliased {
            case let .tensor(s1, t1) where s1.contiguousSize == s.contiguousSize:
                return .tensor(s, t1)
            case let .tensor(s1, t1)
                    where s1.contiguousSize == s.contiguousSize:
                return .tensor(s, t1)
            default: return .invalid
            }

        case let .apply(f, vv):
            switch f.type.unaliased {
            case let .pointer(.function(actual, ret)),
                 let .function(actual, ret):
                guard actual == vv.map({$0.type}) else { fallthrough }
                return ret
            default:
                return .invalid
            }

        case let .extract(from: v, at: indices):
            return v.type.elementType(at: indices) ?? .invalid

        case let .insert(src, to: dest, at: indices):
            guard let elementType = dest.type.elementType(at: indices), elementType == src.type else {
                return .invalid
            }
            return dest.type

        case let .allocateStack(type, n):
            guard n > 0 else { return .invalid }
            return .pointer(type)

        case let .load(v):
            guard case let .pointer(t) = v.type.unaliased else { return .invalid }
            return t

        case let .elementPointer(v, ii):
            guard case let .pointer(t) = v.type else { return .invalid }
            return t.elementType(at: ii).flatMap(Type.pointer) ?? .invalid

        case let .bitCast(_, t):
//            guard v.type.size == t.size else { return .invalid }
            return t

        case let .allocateBox(t):
            return .box(t)

        case let .allocateHeap(t, count: _):
            return .pointer(t)

        case let .projectBox(v):
            guard case let .box(t) = v.type.unaliased else { return .invalid }
            return .pointer(t)

        case .store, .copy, .deallocate,
             .branch, .conditional, .return, .retain, .release, .trap:
            return .void
        }
    }
}

// MARK: - Operands

extension Instruction : User {
    public var operands: [Use] {
        return kind.operands
    }
}

extension InstructionKind {
    public var operands: [Use] {
        switch self {
        case let .numericBinary(_, op1, op2),
             let .booleanBinary(_, op1, op2),
             let .compare(_, op1, op2),
             let .dot(op1, op2),
             let .insert(op1, to: op2, at: _),
             let .reduce(_, op1, initial: op2, _),
             let .random(_, from: op1, upTo: op2):
            return [op1, op2]
        case let .not(op), let .numericUnary(_, op), let .scan(_, op, _),
             let .transpose(op), let .slice(op, at: _), let .shapeCast(op, _),
             let .dataTypeCast(op, _), let .bitCast(op, _), let .return(op?),
             let .extract(from: op, at: _),
             let .store(op, _), let .load(op), let .elementPointer(op, _),
             let .deallocate(op), let .allocateHeap(_, count: op),
             let .projectBox(op), let .release(op), let .retain(op):
            return [op]
        case .concatenate(let ops, _),
             .branch(_, let ops):
            return ops
        case let .conditional(cond, _, thenArgs, _, elseArgs):
            return [cond] + thenArgs + elseArgs
        case let .apply(f, args):
            return [f] + args
        case let .copy(from: op1, to: op2, count: op3),
             let .select(op1, op2, by: op3):
            return [op1, op2, op3]
        case let .literal(lit, _):
            return lit.operands
        case .return(nil), .allocateBox, .trap, .allocateStack:
            return []
        }
    }
}

public extension Literal {
    var operands: [Use] {
        func literalOperands(in use: Use) -> [Use] {
            switch use {
            case let .literal(_, lit):
                return lit.operands
            default:
                return []
            }
        }
        switch self {
        case let .array(ops), let .tensor(ops), let .tuple(ops):
            return ops.flatMap(literalOperands(in:))
        case let .struct(tups):
            return tups.map{$1}.flatMap(literalOperands(in:))
        default:
            return []
        }
    }
}

// MARK: - Substitution utilities

public extension Instruction {
    func substitute(_ newUse: Use, for use: Use) {
        kind = kind.substituting(newUse, for: use)
    }
}

public extension InstructionKind {
    /// Substitutes new use for old use
    /// - Note: The current implementation is a vanilla tedious switch 
    /// matching all the permutations (a.k.a. very bad).
    func substituting(_ new: Use, for old: Use) -> InstructionKind {
        let condSubst = {$0 == old ? new : $0}
        switch self {
        case .branch(let dest, let args):
            return .branch(dest, args.map(condSubst))
        case let .conditional(cond, thenBB, thenArgs, elseBB, elseArgs):
            let newCond = cond == old ? new : cond
            return .conditional(newCond,
                                thenBB, thenArgs.map(condSubst),
                                elseBB, elseArgs.map(condSubst))
        case .return(old?):
            return .return(new)
        case .literal(let lit, let ty):
            return .literal(lit.substituting(new, for: old), ty)
        case .numericUnary(let fun, old):
            return .numericUnary(fun, new)
        case .numericBinary(let fun, old, old):
            return .numericBinary(fun, new, new)
        case .numericBinary(let fun, old, let use2):
            return .numericBinary(fun, new, use2)
        case .numericBinary(let fun, let use1, old):
            return .numericBinary(fun, use1, new)
        case .booleanBinary(let fun, old, old):
            return .booleanBinary(fun, new, new)
        case .booleanBinary(let fun, old, let use2):
            return .booleanBinary(fun, new, use2)
        case .booleanBinary(let fun, let use1, old):
            return .booleanBinary(fun, use1, new)
        case .compare(let fun, old, old):
            return .compare(fun, new, new)
        case .compare(let fun, old, let use2):
            return .compare(fun, new, use2)
        case .compare(let fun, let use1, old):
            return .compare(fun, use1, new)
        case .not(old):
            return .not(new)
        case let .concatenate(uses, axis: axis):
            return .concatenate(uses.map(condSubst), axis: axis)
        case .transpose(old):
            return .transpose(new)
        case .slice(old, at: let range):
            return .slice(new, at: range)
        case .reduce(.function(old), old, initial: old, let dims):
            return .reduce(.function(new), new, initial: new, dims)
        case .reduce(.function(old), old, initial: let v1, let dims):
            return .reduce(.function(new), new, initial: v1, dims)
        case .reduce(.function(old), let v1, initial: old, let dims):
            return .reduce(.function(new), v1, initial: new, dims)
        case .reduce(.function(let v1), old, initial: old, let dims):
            return .reduce(.function(v1), new, initial: new, dims)
        case .reduce(.function(let v1), let v2, initial: old, let dims):
            return .reduce(.function(v1), v2, initial: new, dims)
        case .reduce(.function(let v1), old, initial: let v2, let dims):
            return .reduce(.function(v1), new, initial: v2, dims)
        case .reduce(.function(old), let v1, initial: let v2, let dims):
            return .reduce(.function(new), v1, initial: v2, dims)
        case .dot(old, let use2):
            return .dot(new, use2)
        case .dot(let use1, old):
            return .dot(use1, new)
        case .dot(old, old):
            return .dot(new, new)
        case .shapeCast(old, let shape):
            return .shapeCast(new, shape)
        case .dataTypeCast(old, let type):
            return .dataTypeCast(new, type)
        case let .apply(f, uses):
            return .apply(f, uses.map(condSubst))
        case .extract(from: old, at: let i):
            return .extract(from: new, at: i)
        case .insert(old, to: old, at: let indices):
            return .insert(new, to: new, at: indices)
        case .insert(old, to: let use1, at: let indices):
            return .insert(new, to: use1, at: indices)
        case .insert(let use1, to: old, at: let indices):
            return .insert(use1, to: new, at: indices)
        case .bitCast(old, let targetT):
            return .bitCast(new, targetT)
        case .elementPointer(old, let indices):
            return .elementPointer(new, indices)
        case .store(old, to: let dest):
            return .store(new, to: dest)
        case .store(let val, to: old):
            return .store(val, to: new)
        case .load(old):
            return .load(new)
        case .allocateHeap(let ty, count: old):
            return .allocateHeap(ty, count: new)
        case .deallocate(old):
            return .deallocate(new)
        case .copy(from: old, to: old, count: old):
            return .copy(from: new, to: new, count: new)
        case .copy(from: old, to: old, count: let v3):
            return .copy(from: new, to: new, count: v3)
        case .copy(from: old, to: let v2, count: old):
            return .copy(from: new, to: v2, count: new)
        case .copy(from: old, to: let v2, count: let v3):
            return .copy(from: new, to: v2, count: v3)
        case .copy(from: let v1, to: old, count: old):
            return .copy(from: v1, to: new, count: new)
        case .copy(from: let v1, to: old, count: let v3):
            return .copy(from: v1, to: new, count: v3)
        case .copy(from: let v1, to: let v2, count: old):
            return .copy(from: v1, to: v2, count: new)
        case .random(let shape, from: old, upTo: old):
            return .random(shape, from: new, upTo: new)
        case .random(let shape, from: old, upTo: let v2):
            return .random(shape, from: new, upTo: v2)
        case .random(let shape, from: let v1, upTo: old):
            return .random(shape, from: v1, upTo: new)
        case .select(old, old, by: old):
            return .select(new, new, by: new)
        case .select(old, old, by: let v3):
            return .select(new, new, by: v3)
        case .select(let v1, old, by: old):
            return .select(v1, new, by: new)
        case .select(old, let v2, by: old):
            return .select(new, v2, by: new)
        case .select(old, let v2, by: let v3):
            return .select(new, v2, by: v3)
        case .select(let v1, old, by: let v3):
            return .select(v1, new, by: v3)
        case .select(let v1, let v2, by: old):
            return .select(v1, v2, by: new)
        default:
            return self
        }
    }
}

// MARK: - Opcode decomposition

public enum Opcode {
    case branch
    case conditional
    case `return`
    case literal
    case dataTypeCast
    case scan
    case reduce
    case dot
    case concatenate
    case transpose
    case slice
    case shapeCast
    case bitCast
    case extract
    case insert
    case apply
    case allocateStack
    case allocateHeap
    case allocateBox
    case projectBox
    case retain
    case release
    case deallocate
    case load
    case store
    case elementPointer
    case copy
    case trap
    case numericBinaryOp(NumericBinaryOp)
    case compare(ComparisonOp)
    case numericUnaryOp(NumericUnaryOp)
    case not
    case booleanBinaryOp(BooleanBinaryOp)
    case random
    case select
}

/// Instruction ADT decomposition (opcodes, keywords, operands)
/// - Note: When adding a new instruction, you should insert its
/// corresponding opcode here
public extension InstructionKind {
    var opcode: Opcode {
        switch self {
        case .branch: return .branch
        case .conditional: return .conditional
        case .return: return .return
        case .literal: return .literal
        case .numericUnary(let op, _): return .numericUnaryOp(op)
        case .numericBinary(let op, _, _): return .numericBinaryOp(op)
        case .booleanBinary(let op, _, _): return .booleanBinaryOp(op)
        case .not: return .not
        case .compare(let op, _, _): return .compare(op)
        case .dataTypeCast: return .dataTypeCast
        case .scan: return .scan
        case .reduce: return .reduce
        case .dot: return .dot
        case .concatenate: return .concatenate
        case .transpose: return .transpose
        case .slice: return .slice
        case .shapeCast: return .shapeCast
        case .bitCast: return .bitCast
        case .extract: return .extract
        case .insert: return .insert
        case .apply: return .apply
        case .allocateStack: return .allocateStack
        case .allocateHeap: return .allocateHeap
        case .allocateBox: return .allocateBox
        case .projectBox: return .projectBox
        case .retain: return .retain
        case .release: return .release
        case .deallocate: return .deallocate
        case .load: return .load
        case .store: return .store
        case .elementPointer: return .elementPointer
        case .copy: return .copy
        case .trap: return .trap
        case .random: return .random
        case .select: return .select
        }
    }
}

extension Opcode : Equatable {
    public static func == (lhs: Opcode, rhs: Opcode) -> Bool {
        switch (lhs, rhs) {
        case (.branch, .branch): return true
        case (.conditional, .conditional): return true
        case (.return, .return): return true
        case (.dataTypeCast, .dataTypeCast): return true
        case (.scan, .scan): return true
        case (.reduce, .reduce): return true
        case (.dot, .dot): return true
        case (.concatenate, .concatenate): return true
        case (.transpose, .transpose): return true
        case (.slice, .slice): return true
        case (.shapeCast, .shapeCast): return true
        case (.bitCast, .bitCast): return true
        case (.extract, .extract): return true
        case (.insert, .insert): return true
        case (.apply, .apply): return true
        case (.allocateStack, .allocateStack): return true
        case (.allocateHeap, .allocateHeap): return true
        case (.allocateBox, .allocateBox): return true
        case (.projectBox, .projectBox): return true
        case (.retain, .retain): return true
        case (.release, .release): return true
        case (.deallocate, .deallocate): return true
        case (.load, .load): return true
        case (.store, .store): return true
        case (.elementPointer, .elementPointer): return true
        case (.copy, .copy): return true
        case (.trap, .trap): return true
        case (.literal, .literal): return true
        case let (.numericBinaryOp(o1), .numericBinaryOp(o2)): return o1 == o2
        case let (.compare(o1), .compare(o2)): return o1 == o2
        case let (.numericUnaryOp(o1), .numericUnaryOp(o2)): return o1 == o2
        case let (.booleanBinaryOp(o1), .booleanBinaryOp(o2)): return o1 == o2
        case (.not, .not): return true
        case (.random, .random): return true
        case (.select, .select): return true
        default: return false
        }
    }
}
