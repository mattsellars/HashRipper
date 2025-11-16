//
//  DeploymentListView.swift
//  HashRipper
//
//  Main view showing all firmware deployments (active and completed)
//
import SwiftUI
import SwiftData

struct DeploymentListView: View {
    private let store = FirmwareDeploymentStore.shared
    @State private var selectedDeployment: FirmwareDeployment?
    @State private var activeDeployments: [FirmwareDeployment] = []
    @State private var completedDeployments: [FirmwareDeployment] = []

    static let windowGroupId = "deployment-list"

    var body: some View {
        NavigationSplitView {
            // Sidebar: List of deployments
            List(selection: $selectedDeployment) {
                if !activeDeployments.isEmpty {
                    Section("Active Deployments") {
                        ForEach(activeDeployments, id: \.persistentModelID) { deployment in
                            NavigationLink(value: deployment) {
                                DeploymentRowView(deployment: deployment)
                            }
                        }
                    }
                }

                if !completedDeployments.isEmpty {
                    Section("Completed Deployments") {
                        ForEach(completedDeployments, id: \.persistentModelID) { deployment in
                            NavigationLink(value: deployment) {
                                DeploymentRowView(deployment: deployment)
                            }
                        }
                    }
                }

                if activeDeployments.isEmpty && completedDeployments.isEmpty {
                    ContentUnavailableView {
                        Label("No Deployments", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Start a firmware deployment from the Firmware Releases view")
                    }
                }
            }
            .navigationTitle("Deployments")
            .frame(minWidth: 300)
            .onAppear {
                loadDeployments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deploymentStoreInitialized)) { _ in
                // Store finished initial load - refresh our data
                loadDeployments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deploymentCreated)) { _ in
                loadDeployments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deploymentCompleted)) { _ in
                loadDeployments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deploymentDeleted)) { _ in
                loadDeployments()
            }

        } detail: {
            if let deployment = selectedDeployment {
                // Check if deployment still exists in store
                let deploymentExists = activeDeployments.contains(where: { $0.persistentModelID == deployment.persistentModelID }) ||
                                      completedDeployments.contains(where: { $0.persistentModelID == deployment.persistentModelID })

                if deploymentExists {
                    DeploymentDetailView(deployment: deployment)
                        .id(deployment.persistentModelID)
                } else {
                    // Deployment was deleted, clear selection
                    ContentUnavailableView {
                        Label("Deployment Deleted", systemImage: "trash")
                    } description: {
                        Text("The selected deployment has been removed")
                    }
                    .onAppear {
                        selectedDeployment = nil
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Select a Deployment", systemImage: "arrow.left.circle")
                } description: {
                    Text("Choose a deployment from the list to view details")
                }
            }
        }
    }

    private func loadDeployments() {
        activeDeployments = store.activeDeployments
        completedDeployments = store.completedDeployments
    }
}
