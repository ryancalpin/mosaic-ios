// Sources/Mosaic/Models/Workflow.swift
import Foundation
import SwiftData

@Model
public final class Workflow {
    public var name: String = ""
    public var desc: String = ""
    public var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade)
    public var steps: [WorkflowStep] = []

    public init() {}

    public var orderedSteps: [WorkflowStep] {
        steps.sorted { $0.position < $1.position }
    }
}

@Model
public final class WorkflowStep {
    public var command: String = ""
    public var delayAfter: Double = 0.0
    public var position: Int = 0
    public var workflow: Workflow?

    public init() {}
}
