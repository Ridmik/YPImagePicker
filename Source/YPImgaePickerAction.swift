//
//  YPImgaePickerAction.swift
//  YPImagePicker
//
//  Created by Ankur on 6/7/21.
//

import Foundation

public enum YPImagePickerEvent: String {
    case eventOpenGalleryView = "open_gallery_view"
}

public enum YPImagePickerAction: String {
    case action
}

extension String {
    static let actionOpenGalleryView = "user comes to gallery fragment"
}
