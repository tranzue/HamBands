//
//  HamBandsWidgetBundle.swift
//  HamBandsWidget
//
//  Created by Taylor Transue on 5/31/26.
//

import WidgetKit
import SwiftUI

@main
struct HamBandsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HamBandsWidget()
        SolarFluxWidget()
    }
}
