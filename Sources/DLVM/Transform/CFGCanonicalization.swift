//
//  CFGCanonicalization.swift
//  DLVM
//
//  Copyright 2016-2018 The DLVM Team.
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

/// Canonicalizes control flow graph so that it becomes "reversible": its
/// transpose is also a valid control flow graph.
/// - All basic blocks have at most two predecessors.
/// - There is exactly one exit basic block.

open class CFGCanonicalization : TransformPass {
    public typealias Body = Function
    
    public static func run(on body: Function) -> Bool {
        var changed = false
        let builder = IRBuilder(function: body)

        /// Perform general CFG canonicalizations.
        /// Merge multiple exits.
        var cfg = body.analysis(from: ControlFlowGraphAnalysis.self)
        if body.premise.exits.count > 1 {
            let newExitArg = (body.makeFreshName("exit_value"), body.returnType)
            let newExit = BasicBlock(name: body.makeFreshBasicBlockName("exit"),
                                     arguments: [newExitArg],
                                     parent: body)
            for (exit, returnInst) in body.premise.exits {
                guard case let .return(use) = returnInst.kind else {
                    fatalError("Invalid exit return instruction")
                }
                returnInst.kind = .branch(newExit, use.flatMap { [$0] } ?? [])
                cfg.insertEdge(from: exit, to: newExit)
            }
            body.append(newExit)
            builder.move(to: newExit)
            builder.return(%newExit.arguments[0])
        }

        /// Canonicalize loops.
        cfg = body.analysis(from: ControlFlowGraphAnalysis.self)
        var loopInfo = body.analysis(from: LoopAnalysis.self)
        for loop in loopInfo.uniqueLoops {
            /// If loop doesn't have a preheader, insert one.
            if loop.preheader == nil {
                insertPreheader(for: loop, loopInfo: &loopInfo, controlFlow: cfg)
                changed = true
            }
            /// Next, check to make sure that all exit nodes of the loop only
            /// have predecessors that are inside of the loop. This check
            /// guarantees that the loop preheader/header will dominate the
            /// exit blocks. If the exit block has predecessors from outside of
            /// the loop, split the edge now.
            if !loop.hasDedicatedExits {
                changed = formDedicatedExits(
                    for: loop, loopInfo: &loopInfo, controlFlow: cfg) || changed
            }
        }
        return changed
    }

    public static func insertPreheader(
        for loop: Loop, loopInfo: inout LoopInfo,
        controlFlow cfg: DirectedGraph<BasicBlock>
    ) {
        /// Gather original predecessors of header
        let preds = cfg.predecessors(of: loop.header)
            .lazy.filter { !loop.contains($0) }
        /// Create preheader and hoist predecessors to it
        let preheader = loop.header.hoistPredecessorsToNewBlock(
            named: "preheader", hoisting: preds)
        /// Make the preheader a part of the parent loop if it exists
        if let parent = loop.parent {
            loopInfo.innerMostLoops[preheader] = parent
            parent.blocks.insert(preheader, before: loop.header)
        }
    }

    public static func formDedicatedExits(
        for loop: Loop, loopInfo: inout LoopInfo,
        controlFlow cfg: DirectedGraph<BasicBlock>
    ) -> Bool {
        var changed = false
        for exit in loop.exits {
            /// Gather predecessors that are inside loop
            let preds = cfg.predecessors(of: exit)
            let insidePreds = preds.lazy.filter { loop.contains($0) }
            guard insidePreds.count < preds.count else { continue }
            /// Create new exit and hoist inside-predecessors to it
            let newExit = exit.hoistPredecessorsToNewBlock(
                named: "exit", hoisting: insidePreds)
            /// Make the new exit a part of the parent loop if it exists
            if let parent = loop.parent {
                loopInfo.innerMostLoops[newExit] = parent
                parent.blocks.insert(newExit, before: exit)
            }
            changed = true
        }
        return changed
    }
}
