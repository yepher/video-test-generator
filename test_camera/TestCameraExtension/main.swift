//
//  main.swift
//  TestCameraExtension
//
//  Entry point for the camera system extension.
//

import Foundation
import CoreMediaIO

let providerSource = CameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
