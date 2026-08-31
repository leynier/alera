use super::{AleraApp,SidebarGroupBy,SidebarSortBy};
use crate::model::{Project,Workspace};

impl AleraApp {
    pub(super) fn pinned_workspace_groups<'a>(&self,projects:&[&'a Project],filter:&str)->Vec<Vec<(&'a Project,&'a Workspace)>> {
        if self.sidebar_group_by==SidebarGroupBy::None || self.sidebar_workspace_sort==SidebarSortBy::Activity {
            let mut pinned=projects.iter().flat_map(|project|self.visible_workspaces(project,filter,true,false)
                .into_iter().map(|workspace|(*project,workspace))).collect();
            self.sort_sidebar_workspace_pairs(&mut pinned);
            return vec![pinned];
        }
        projects.iter().map(|project|{
            let mut workspaces=self.visible_workspaces(project,filter,true,false);
            self.sort_sidebar_workspaces(&mut workspaces);
            workspaces.into_iter().map(|workspace|(*project,workspace)).collect()
        }).collect()
    }
}
