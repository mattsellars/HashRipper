//
//  FirmwareDeploymentProgressView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct FirmwareDeploymentProgressView: View {
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                
                if deploymentManager.deployments.isEmpty {
                    emptyStateView
                } else {
                    deploymentListView
                }
                
                Divider()
                
                footerView
                    .padding(16)
            }
        }
        .frame(width: 900, height: 600)
        .navigationTitle("Firmware Deployments")
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Firmware Deployments")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !deploymentManager.activeDeployments.isEmpty {
                    Text("\(deploymentManager.activeDeployments.count) active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
            
            if !deploymentManager.activeDeployments.isEmpty {
                Text("Deploying firmware to \(deploymentManager.activeDeployments.count) miners")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if !deploymentManager.deployments.isEmpty {
                Text("All deployments completed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Deployments")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Start firmware deployments from the firmware releases view")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deploymentListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(deploymentManager.deployments) { deployment in
                    DeploymentDetailRow(deployment: deployment)
                }
            }
            .padding(16)
        }
    }
    
    private var footerView: some View {
        HStack {
            Text("\(deploymentManager.deployments.count) total deployments")
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !deploymentManager.deployments.isEmpty {
                Button("Clear Completed") {
                    deploymentManager.clearCompletedDeployments()
                }
                .disabled(deploymentManager.deployments.allSatisfy { $0.status.isActive })
            }
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

struct DeploymentDetailRow: View {
    let deployment: MinerDeploymentItem
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            Image(systemName: deployment.status.iconName)
                .foregroundColor(deployment.status.color)
                .font(.title2)
                .frame(width: 30)
            
            // Miner Information
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(deployment.miner.hostName)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(deployment.firmwareRelease.name)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
                
                HStack {
                    Text(deployment.miner.ipAddress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(deployment.miner.minerDeviceDisplayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(deployment.addedDate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar (for active uploads)
            if case .uploadingMiner(let progress) = deployment.status {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    ProgressView(value: progress)
                        .frame(width: 80)
                }
            } else if case .uploadingWww(let progress) = deployment.status {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    ProgressView(value: progress)
                        .frame(width: 80)
                }
            } else if case .waitingForRestart(let seconds) = deployment.status {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(seconds)s")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(0.8)
                        .frame(width: 80)
                }
            } else if case .monitoringRestart(let seconds, let hashRate) = deployment.status {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(seconds)s")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(String(format: "%.1f", hashRate)) GH/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(0.8)
                        .frame(width: 80)
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                switch deployment.status {
                case .failed:
                    Button {
                        deploymentManager.retryDeployment(deployment)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Retry deployment")
                    
                case .pending, .preparingMiner, .uploadingMiner, .minerUploadComplete, .preparingWww, .uploadingWww, .wwwUploadComplete, .waitingForRestart, .monitoringRestart, .restartingManually:
                    Button {
                        deploymentManager.cancelDeployment(deployment)
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel deployment")
                    
                default:
                    EmptyView()
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .overlay(
            // Status Text Overlay
            VStack {
                Spacer()
                HStack {
                    Text(deployment.status.displayText)
                        .font(.caption)
                        .foregroundColor(deployment.status.color)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        )
    }
}