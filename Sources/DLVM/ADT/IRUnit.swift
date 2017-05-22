//
//  IRUnit.swift
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

public protocol EquatableByReference : class, Equatable {}
public protocol HashableByReference : EquatableByReference, Hashable {}

public extension EquatableByReference {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs === rhs
    }
}

public extension HashableByReference {
    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
}

public protocol IRUnit : class, HashableByReference, Verifiable {
    associatedtype Parent : IRCollection
    unowned var parent: Parent { get set }
}

public extension IRUnit
    where Parent.Iterator.Element == Self, Parent.Index == Int, Parent.IndexDistance == Int,
          Parent.Indices == Parent.Base.Indices, Parent.SubSequence == Parent.Base.SubSequence,
          Parent.Element == Parent.Base.Iterator.Element, Parent.Element == Parent.Base.Element,
          Parent.Element == Self, Parent.Index == Parent.Base.Index,
          Parent.IndexDistance == Parent.Base.IndexDistance {
    var indexInParent: Int {
        guard let index = parent.index(of: self) else {
            preconditionFailure("Self does not exist in parent basic block")
        }
        return index
    }

    func removeFromParent() {
        parent.remove(self)
    }
}
