

# Function to cluster dataset
cluster_customer_transactions <- function(df)
{
  
  num_points = nrow(unique(df))
  
  if (num_points == 1)
  {
    df$cluster_id = 1
    clusters_info = data.frame(size = 1, max_diss = 0, av_diss = 0, diameter=0, separation = 0)
  }
  
  if (num_points == 2) 
  {
    
    df$cluster_id = 1
    
    # A cheat to 1 get class clusterization and cluster details
    p_clusters <- pam(rbind(df,df), k=1)
    clusters_info <- as.data.frame(p_clusters$clusinfo)
    clusters_info$size = clusters_info$size / 2
    clusters_info$av_diss = clusters_info$av_diss * 2
    
  }
  
  if (num_points >= 3)
  {
    
    # Clusterize (all transactions and most important categories)
    p_clusters <- pamk(df, krange=2:min(10, num_points-1), critout=F)
    clusters_info <- p_clusters$pamobject$clusinfo
    df$cluster_id <- p_clusters$pamobject$clustering
    
  }
  
  clusters_center <- df[order(cluster_id),.(cluster_mean_lat=mean(pos_atm_lat,na.rm=T),cluster_mean_lon=mean(pos_atm_lon,na.rm=T)),by=.(cluster_id)]
  clusters_info <- cbind(clusters_center, clusters_info)
  colnames(clusters_info)[colnames(clusters_info) %in% c('size','max_diss','av_diss','diameter','separation')] <- c('cluster_size','cluster_max_diss','cluster_av_diss','cluster_diameter','cluster_separation')
  
  # Rank current POS cluster by different parameters
  clusters_info$cluster_rank_by_size <- order(-clusters_info$cluster_size)
  clusters_info$cluster_rank_by_max_diss <- order(-clusters_info$cluster_max_diss)
  clusters_info$cluster_rank_by_av_diss <- order(-clusters_info$cluster_av_diss)
  clusters_info$cluster_rank_by_diameter <- order(-clusters_info$cluster_diameter)
  clusters_info$cluster_rank_by_separation <- order(-clusters_info$cluster_separation)
  
  # Ratio of current POS cluster to max POS clusters
  clusters_info$cluster_max_diss_rate_max <- clusters_info$cluster_max_diss / (max(clusters_info$cluster_max_diss)+0.001)
  clusters_info$cluster_size_rate_max = clusters_info$cluster_size / (max(clusters_info$cluster_size)+0.001)
  clusters_info$cluster_av_diss_rate_max = clusters_info$cluster_av_diss / (max(clusters_info$cluster_av_diss)+0.001)
  clusters_info$cluster_diameter_rate_max = clusters_info$cluster_diameter / (max(clusters_info$cluster_diameter)+0.001)
  clusters_info$cluster_separation_rate_max = clusters_info$cluster_separation / (max(clusters_info$cluster_separation) + 0.001)
  
  clusters_info$cluster_max_diss_rate_avg <- clusters_info$cluster_max_diss / (mean(clusters_info$cluster_max_diss)+0.001)
  clusters_info$cluster_size_rate_avg = clusters_info$cluster_size / (mean(clusters_info$cluster_size)+0.001)
  clusters_info$cluster_av_diss_rate_avg = clusters_info$cluster_av_diss / (mean(clusters_info$cluster_av_diss)+0.001)
  clusters_info$cluster_diameter_rate_avg = clusters_info$cluster_diameter / (mean(clusters_info$cluster_diameter)+0.001)
  clusters_info$cluster_separation_rate_avg = clusters_info$cluster_separation / (mean(clusters_info$cluster_separation) + 0.001)
  
  clusters_info$cluster_max_diss_rate_min <- clusters_info$cluster_max_diss / (min(clusters_info$cluster_max_diss)+0.001)
  clusters_info$cluster_size_rate_min = clusters_info$cluster_size / (min(clusters_info$cluster_size)+0.001)
  clusters_info$cluster_av_diss_rate_min = clusters_info$cluster_av_diss / (min(clusters_info$cluster_av_diss)+0.001)
  clusters_info$cluster_diameter_rate_min = clusters_info$cluster_diameter / (min(clusters_info$cluster_diameter)+0.001)
  clusters_info$cluster_separation_rate_min = clusters_info$cluster_separation / (min(clusters_info$cluster_separation) + 0.001)
  
  # Ratio of current cluster to first cluster
  
  
  
  return(list(clusters_info=clusters_info, cluster_id=df$cluster_id))
  
}

# A function to calcluate distance-based attributes
# Input: customer transactions
# Output: same transactions enriched with new attributes
process_customer <- function(current_transactions,use_additional_points, thread)
{
  
  require(fpc)
  
  
  
  # toDO: compute candidatePoints
  # toDO: current_trsansaction <- rbind(current_transcations, candidatePoints)
  
  
  # Number of input transactions
  num_points <- nrow(current_transactions)
  
  current_transactions$is_additional_point <- 0
  
  # We need new points so we use only distinct points
  unique_points <- unique(current_transactions[,.(pos_atm_orig_lat,pos_atm_orig_lon)])
  
  if (use_additional_points & nrow(unique_points) > 1)
  {
    
    
    # Define number of clusters: 2,3,4 -> 1; 5,6,7,8 -> 2 and so on
    num_clusters <- floor(nrow(unique_points) / 4 + 0.99)
    
    # Clusterize transaction data
    p_clusters = cluster::pam(unique_points, k=num_clusters)
    unique_points$additional_cluster <- p_clusters$clustering
    
    # Compute cluster centers and volumes
    additional_points <- unique_points[,.(n=.N,pos_atm_orig_lat=mean(pos_atm_orig_lat),pos_atm_orig_lon=mean(pos_atm_orig_lon)),by=.(additional_cluster)]
    
    # Remove 1-point clusters (those points are not new)
    additional_points <- additional_points[n>1,]
    additional_points$is_additional_point = 1
    num_additional_points = nrow(additional_points)
    
    # Delete unnecessary
    additional_points$additional_cluster <- NULL
    additional_points$n <- NULL
    
    # Setup logging for one thread
    if (thread==48) print(paste("clusterized ",nrow(unique_points)," unique points into ",num_clusters," clusters, got ",num_additional_points," points",sep=""))
    
    # Add new points to the dataset
    all_transactions<-rbind(current_transactions, additional_points, fill=T)
  
  }
  if (!use_additional_points | nrow(unique_points) == 1)
  {
    all_transactions <- current_transactions
    
  }
      
  all_transactions$id <- as.numeric(row.names(all_transactions))
  current_transactions$id <- as.numeric(row.names(current_transactions))
  
  # Compute distance matrix bewteen all transactions
  transactionsDistMatrix <- as.matrix(dist(all_transactions[,.(pos_atm_orig_lat, pos_atm_orig_lon),]))
  
  # When computing stats, use only real transactions (not generated ones)
  if (num_points > 1)
    d <- transactionsDistMatrix[,1:num_points]
  if (num_points == 1)
    d <- transactionsDistMatrix

  
  # Calculate neighborhood attributes
  for (j in c("any","6011","5411","5814","5812","5499","5912","5541","4111","5691","5977","5921","5999","5331","5261","5661"))
  {
    for (z in all_transactions$id)
    {
      
        # Select transactions of particular category (or all)
        if (j == "any")
          type_transaction_ids <- setdiff(current_transactions$id, z)
        else
          type_transaction_ids <- setdiff(current_transactions$id[current_transactions$mcc==j], z)
        
       
        # Compute the number of transactions in epsilon neighborhood using distance matrix
        all_transactions[z,paste("eps_1_cnt_",j,sep="")] <- sum(d[z,type_transaction_ids] < 0.02)
        all_transactions[z,paste("eps_2_cnt_",j,sep="")] <- sum(d[z,type_transaction_ids] < 0.05)
        all_transactions[z,paste("eps_3_cnt_",j,sep="")] <- sum(d[z,type_transaction_ids] < 0.10)

        all_transactions[z,paste("eps_1_rate_",j,sep="")] <- all_transactions[z,paste("eps_1_cnt_",j,sep=""),with=FALSE] / ncol(d)
        all_transactions[z,paste("eps_2_rate_",j,sep="")] <- all_transactions[z,paste("eps_2_cnt_",j,sep=""),with=FALSE] / ncol(d)
        all_transactions[z,paste("eps_3_rate_",j,sep="")] <- all_transactions[z,paste("eps_3_cnt_",j,sep=""),with=FALSE] / ncol(d)

    }
  }
  
  
  # 
  for (i in c(1,3,5,7,9))
  {
    for (j in c("any","6011","5411","5814","5812","5499","5912","5541","4111","5691","5977","5921","5999","5331","5261","5661"))
    {
      # print(paste("processing ",i,"_",j,"\r",sep=""))
      for (z in all_transactions$id)
      {
        
        # Use transactions of particular category
        if (j == "any")
          type_transaction_ids <- setdiff(current_transactions$id, z)
        else
          type_transaction_ids <- setdiff(current_transactions$id[current_transactions$mcc==j], z)
        
        top_n_type <- type_transaction_ids[order(d[z,type_transaction_ids])][1:i]
        top_n_type_distances <- d[z,top_n_type]
        
        if (length(top_n_type_distances) > 0)
        {
          top_n_type_distance <- mean(d[z,top_n_type])
          top_n_type_distance_max <- max(d[z,top_n_type])
        }
        if (length(top_n_type_distances) == 0)
        {
          top_n_type_distance <- 2
          top_n_type_distance_max <- 2
        }
        
        if (j=="any")
        {
          closest_merchant_categories <- current_transactions$mcc[current_transactions$id %in% top_n_type]
          all_transactions[z,paste("top_",i,"_6011_rate",sep="")] <- sum(closest_merchant_categories=="6011") / i
          all_transactions[z,paste("top_",i,"_5411_rate",sep="")] <- sum(closest_merchant_categories=="5411") / i
          all_transactions[z,paste("top_",i,"_5814_rate",sep="")] <- sum(closest_merchant_categories=="5814") / i
          all_transactions[z,paste("top_",i,"_5812_rate",sep="")] <- sum(closest_merchant_categories=="5812") / i
          all_transactions[z,paste("top_",i,"_5499_rate",sep="")] <- sum(closest_merchant_categories=="5499") / i
          all_transactions[z,paste("top_",i,"_5912_rate",sep="")] <- sum(closest_merchant_categories=="5912") / i
          all_transactions[z,paste("top_",i,"_5541_rate",sep="")] <- sum(closest_merchant_categories=="5541") / i
          all_transactions[z,paste("top_",i,"_5691_rate",sep="")] <- sum(closest_merchant_categories=="5691") / i
          all_transactions[z,paste("top_",i,"_5977_rate",sep="")] <- sum(closest_merchant_categories=="5977") / i
          all_transactions[z,paste("top_",i,"_5921_rate",sep="")] <- sum(closest_merchant_categories=="5921") / i
        }
        
        if (is.na(top_n_type_distance)) top_n_type_distance <- 2
        if (is.na(top_n_type_distance_max)) top_n_type_distance_max <- 2
        
        attr_name <- paste("top_",i,"_",j,"_mean_distance",sep="")
        all_transactions[z,attr_name] <- top_n_type_distance

        attr_name <- paste("top_",i,"_",j,"_max_distance",sep="")
        all_transactions[z,attr_name] <- top_n_type_distance_max
        
      }
    }
  }
  
  
  
  
  # ToDO: Filter outlier transactions, set their cluster to 0
  
  
  # Clustering
  
  categories_to_cluster <- c('all')
  for (merchant_category in categories_to_cluster)
  {
    
    # Select datsets
    if (merchant_category == "all")
      transactions_to_cluster <- current_transactions[, c("pos_atm_lat","pos_atm_lon")]
    if (merchant_category != "all")
      transactions_to_cluster <- current_transactions[mcc==merchant_category, c("pos_atm_lat","pos_atm_lon")]
    
    # Set new attribute names
    clustering_attr_name = paste("cluster_",merchant_category, sep="")
    cluster_dist_attr_name = paste("cluster_dist_",merchant_category, sep="")
    cluster_cnt_attr_name = paste("cluster_cnt_",merchant_category, sep="")
    
    # When no transactions of specific category, set clustering data to dummy values
    if (nrow(transactions_to_cluster)==0)
    {
      all_transactions[,clustering_attr_name] <- 0
      
      # Compute Distance to current cluster center
      all_transactions[,cluster_dist_attr_name] = 2
      
      all_transactions[,cluster_cnt_attr_name] <- 0
      
    }
    else
    {
      
      # Cluster transactions of current MCC type
      result <- cluster_customer_transactions(transactions_to_cluster)
    
      # Get resulting cluster number
      all_transactions[is_additional_point==0,clustering_attr_name] <- result$cluster_id
      
      # Merge cluster data (for transaction points)
      all_transactions <- merge(all_transactions, result$clusters_info, by.x=clustering_attr_name, by.y="cluster_id", all.x=T, all.y=F)
      
      # Compute distance to current cluster center
      all_transactions[,cluster_dist_attr_name] = computeDist(all_transactions$pos_atm_lat, all_transactions$pos_atm_lon, all_transactions$cluster_mean_lat, all_transactions$cluster_mean_lon)
      
      # Get number of clusters
      all_transactions[,cluster_cnt_attr_name] <- nrow(result$clusters_info)
      
    }
  }
  
  # When processing new points, some attributes will be transfered from nearest real point
  features_to_ignore = c("pos_atm_orig_lat","pos_atm_orig_lon","id","is_additional_point","home_dist","work_dist","center_dist",
  colnames(all_transactions)[substr(colnames(all_transactions),1,3)=="eps"],
  colnames(all_transactions)[substr(colnames(all_transactions),1,3)=="top"])
  features_to_copy = c(setdiff(colnames(all_transactions), features_to_ignore),"top","top_city","top_city_center_dist","top_city_lat","top_city_lon")
  
  
  all_transactions$dist_to_real_transaction <- 0
  all_transactions$closest_real_transaction_id <- 0
  for (z in all_transactions$id[all_transactions$is_additional_point==1])
  {
    closest_point_id <- which.min(d[z,])
    all_transactions[id==z,features_to_copy] <- all_transactions[id==closest_point_id,features_to_copy,with=F]
    all_transactions$dist_to_real_transaction[all_transactions$id==z] <- ifelse(all_transactions$is_additional_point[all_transactions$id==z]==1, min(d[z,]), 0)
    all_transactions$closest_real_transaction_id[all_transactions$id==z] <- ifelse(all_transactions$is_additional_point[all_transactions$id==z]==1, closest_point_id, 0)
  }
  
  # Compute distance to Home (NA for Test)
  all_transactions[,home_dist := sqrt((pos_atm_orig_lat - home_orig_lat)^2 + (pos_atm_orig_lon - home_orig_lon)^2),]
  
  # Compute distance to Work (NA for Test and customers with no Work data)
  all_transactions[,work_dist := sqrt((pos_atm_orig_lat - work_orig_lat)^2 + (pos_atm_orig_lon - work_orig_lon)^2),]
  
  # Compute distance from point to top city center
  all_transactions[,center_dist := sqrt((pos_atm_orig_lat-top_city_lat)^2+(pos_atm_orig_lon - top_city_lon)^2),]
  
  
  
  
  all_transactions
  
}
