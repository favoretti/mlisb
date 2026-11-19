//
//  MarkdownTokenAttributes.swift
//  MarkdownEngine
//
//  Text attributes the styler sets on wiki-links and task checkboxes.
//

import Foundation

extension NSAttributedString.Key {
    public static let wikiLinkID = NSAttributedString.Key("NodeLinkID")
    public static let taskCheckbox = NSAttributedString.Key("TaskCheckbox")
    /// mlisb: a hidden run a line may not wrap inside or around (a link's target).
    static let unbreakable = NSAttributedString.Key("mlisb.unbreakable")
    /// mlisb: a code block line, which may use the room right of the text column.
    static let wideBlock = NSAttributedString.Key("mlisb.wideBlock")
}
