// main.swift
// TetherCam Camera Extension entry point. Runs under registerassistantservice.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import CoreMediaIO
import Foundation

let providerSource = ProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
