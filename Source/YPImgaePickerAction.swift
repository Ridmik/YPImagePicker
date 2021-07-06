//
//  YPImgaePickerAction.swift
//  YPImagePicker
//
//  Created by Ankur on 6/7/21.
//

import Foundation

public enum YPImagePickerEvent: String {
    case eventGalleryViewPermission = "GalleryView_requires_STORAGE_PERMISSION"
}

public enum YPImagePickerAction: String {
    case action
}

extension String {
    static let resultGalleryPermissionDenied = "user denies any permission on gallery fragment"
    static let resultGalleryPermissionAccepts = "user accepts any permission on gallery fragment"
}
